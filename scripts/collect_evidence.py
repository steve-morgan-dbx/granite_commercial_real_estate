"""Collect text-readable execution evidence for every stage of the build into evidence/.

Runs read-only queries through the Databricks SQL Statement API and the REST APIs (via the Databricks CLI),
then writes one JSON file per stage. Workspace hostnames, user emails and paths are scrubbed.

Usage:  python3 scripts/collect_evidence.py --profile <cli-profile> --warehouse <warehouse-id>
            [--catalog smmorgan_catalog] [--schema granite_commercial_real_estate]
"""
import argparse
import datetime
import json
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from export_run_notebooks import scrub  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
EV = ROOT / "evidence"


class Workspace:
    def __init__(self, profile, warehouse):
        self.profile, self.warehouse = profile, warehouse

    def api(self, method, path, body=None):
        cmd = ["databricks", "api", method, path, "-p", self.profile]
        if body is not None:
            cmd += ["--json", json.dumps(body)]
        out = subprocess.run(cmd, capture_output=True, text=True)
        if out.returncode:
            raise RuntimeError(out.stderr.strip()[:500])
        return json.loads(out.stdout or "{}")

    def cli(self, *args):
        out = subprocess.run(["databricks", *args, "-p", self.profile, "-o", "json"], capture_output=True, text=True)
        if out.returncode:
            raise RuntimeError(out.stderr.strip()[:500])
        return json.loads(out.stdout or "{}")

    def sql(self, statement):
        d = self.api("post", "/api/2.0/sql/statements",
                     {"warehouse_id": self.warehouse, "statement": statement, "wait_timeout": "50s",
                      "on_wait_timeout": "CONTINUE"})
        while d.get("status", {}).get("state") in ("PENDING", "RUNNING"):
            time.sleep(3)
            d = self.api("get", f"/api/2.0/sql/statements/{d['statement_id']}")
        if d["status"]["state"] != "SUCCEEDED":
            raise RuntimeError(d["status"].get("error", {}).get("message", "query failed")[:500])
        cols = [c["name"] for c in d["manifest"]["schema"]["columns"]]
        return [dict(zip(cols, r)) for r in (d.get("result", {}).get("data_array") or [])]


def write(name, payload):
    EV.mkdir(exist_ok=True)
    payload = {"collected_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), **payload}
    (EV / name).write_text(scrub(json.dumps(payload, indent=2, default=str)) + "\n")
    print(f"wrote evidence/{name}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True)
    ap.add_argument("--warehouse", required=True)
    ap.add_argument("--catalog", default="smmorgan_catalog")
    ap.add_argument("--schema", default="granite_commercial_real_estate")
    ap.add_argument("--pipeline-name", default="Granite Peak CRE Pipeline")
    ap.add_argument("--app-name", default="granite-cre-portfolio")
    a = ap.parse_args()
    ws, uc = Workspace(a.profile, a.warehouse), f"{a.catalog}.{a.schema}"
    gt = f"/Volumes/{a.catalog}/{a.schema}/artifacts/ground_truth/leases/lease_ground_truth.json"

    # ── Lakeflow ────────────────────────────────────────────────────────────────
    pipes = ws.cli("pipelines", "list-pipelines", "--filter", f"name LIKE '{a.pipeline_name}'")
    pid = pipes[0]["pipeline_id"]
    update = ws.cli("pipelines", "list-updates", pid, "--max-results", "1")["updates"][0]
    events = ws.cli("pipelines", "list-pipeline-events", pid, "--max-results", "250",
                    "--filter", f"update_id = '{update['update_id']}'")
    events = events if isinstance(events, list) else events.get("events", [])
    flows = {}
    for e in events:
        if e.get("event_type") == "flow_progress":
            name = e["origin"].get("flow_name", "").split(".")[-1]
            flows.setdefault(name, e["message"].split(" has ")[-1].rstrip("."))
    tables = ws.sql(f"""SELECT table_name, table_type, comment FROM {a.catalog}.information_schema.tables
                        WHERE table_schema = '{a.schema}' ORDER BY table_name""")
    counts = {}
    for t in tables:
        if t["table_type"] in ("STREAMING_TABLE", "MATERIALIZED_VIEW", "MANAGED"):
            counts[t["table_name"]] = int(ws.sql(f"SELECT count(*) AS n FROM {uc}.{t['table_name']}")[0]["n"])
    write("lakeflow_pipeline_update.json", {
        "pipeline": a.pipeline_name, "update_id": update["update_id"], "state": update["state"],
        "full_refresh": update.get("full_refresh"), "flows": flows, "row_counts": counts})

    # ── Unity Catalog ───────────────────────────────────────────────────────────
    write("unity_catalog_governance.json", {
        "row_filters": ws.sql(f"""SELECT table_name, filter_name, target_columns FROM {a.catalog}.information_schema.row_filters
                                   WHERE table_schema = '{a.schema}' ORDER BY table_name"""),
        "column_masks": ws.sql(f"""SELECT table_name, column_name, mask_name FROM {a.catalog}.information_schema.column_masks
                                    WHERE table_schema = '{a.schema}' ORDER BY table_name, column_name"""),
        "column_tags": ws.sql(f"""SELECT table_name, column_name, tag_name, tag_value FROM {a.catalog}.information_schema.column_tags
                                   WHERE schema_name = '{a.schema}' ORDER BY table_name, column_name"""),
        "table_tags": ws.sql(f"""SELECT table_name, tag_name, tag_value FROM {a.catalog}.information_schema.table_tags
                                  WHERE schema_name = '{a.schema}' ORDER BY table_name"""),
        "fund_access": ws.sql(f"SELECT * FROM {uc}.fund_access ORDER BY group_name"),
        "masked_sample": ws.sql(f"SELECT tenant_id, contact_name, contact_email FROM {uc}.tenant_directory ORDER BY tenant_id LIMIT 3"),
        "lineage_into_gold": ws.sql(f"""SELECT DISTINCT source_table_name, target_table_name FROM system.access.table_lineage
                                         WHERE target_table_catalog = '{a.catalog}' AND target_table_schema = '{a.schema}'
                                           AND source_table_name IS NOT NULL ORDER BY target_table_name, source_table_name"""),
        "table_comments": [t for t in tables if t.get("comment")],
    })

    # ── GenAI: extraction accuracy against generator ground truth ───────────────
    fields = {"tenant_name": "lower(trim(e.tenant_name)) = lower(trim(g.tenant_name))",
              "lease_start": "e.lease_start = to_date(g.lease_start)",
              "lease_end": "e.lease_end = to_date(coalesce(g.pdf_lease_end, g.lease_end))",
              "monthly_rent": "abs(e.monthly_rent - coalesce(g.pdf_monthly_rent, g.monthly_rent)) <= 1",
              "security_deposit": "abs(e.security_deposit - g.security_deposit) <= 1",
              "escalation_type": "lower(e.escalation_type) = lower(g.escalation_type)",
              "renewal_option_count": "e.renewal_option_count = g.renewal_option_count",
              "has_co_tenancy": "e.has_co_tenancy = g.has_co_tenancy",
              "has_termination_right": "e.has_termination_right = g.has_termination_right",
              "termination_right_date": "e.termination_right_date <=> to_date(g.termination_right_date)",
              "has_exclusive_use": "e.has_exclusive_use = g.has_exclusive_use"}
    acc_sql = ", ".join(f"round(avg(CASE WHEN {cond} THEN 1.0 ELSE 0.0 END), 4) AS {f}" for f, cond in fields.items())
    accuracy = ws.sql(f"""SELECT count(*) AS documents, {acc_sql}
                          FROM {uc}.silver_lease_extract e
                          JOIN read_files('{gt}', format => 'json', multiLine => true) g USING (lease_id)""")[0]
    detection = ws.sql(f"""WITH g AS (SELECT lease_id, is_discrepant FROM read_files('{gt}', format => 'json', multiLine => true)),
                                amended AS (SELECT DISTINCT lease_id FROM {uc}.bronze_commlease WHERE header__operation = 'U')
                           SELECT count_if(g.is_discrepant) AS planted_discrepancies,
                                  count_if(g.is_discrepant AND d.lease_id IS NOT NULL) AS planted_detected,
                                  count_if(NOT g.is_discrepant AND d.lease_id IS NOT NULL AND m.lease_id IS NOT NULL) AS erp_amendments_detected,
                                  count_if(NOT g.is_discrepant AND d.lease_id IS NOT NULL AND m.lease_id IS NULL) AS unexplained_flags
                           FROM g LEFT JOIN {uc}.lease_discrepancies d USING (lease_id) LEFT JOIN amended m USING (lease_id)""")[0]
    write("genai_document_extraction.json", {
        "method": "ai_parse_document (v2.0) + ai_extract (v2.1) inside the Lakeflow pipeline",
        "field_accuracy_vs_ground_truth": accuracy, "discrepancy_detection": detection,
        "deal_documents": ws.sql(f"""SELECT doc_type, count(*) AS docs, count(asking_price) AS with_asking_price,
                                            sum(size(tenant_list)) AS in_place_leases_extracted
                                     FROM {uc}.deal_abstract GROUP BY doc_type ORDER BY doc_type"""),
        "sample_abstract": ws.sql(f"""SELECT lease_id, tenant_name, lease_start, lease_end, monthly_rent, renewal_option_count,
                                             has_co_tenancy, co_tenancy_terms, has_termination_right, termination_right_date,
                                             abstract_confidence, review_status
                                      FROM {uc}.lease_abstract WHERE has_co_tenancy ORDER BY lease_id LIMIT 3"""),
    })

    # ── ML ──────────────────────────────────────────────────────────────────────
    model = ws.api("get", f"/api/2.1/unity-catalog/models/{uc}.renewal_propensity")
    versions = ws.api("get", f"/api/2.1/unity-catalog/models/{uc}.renewal_propensity/versions").get("model_versions", [])
    latest = max(versions, key=lambda v: v["version"]) if versions else {}
    run = ws.api("get", f"/api/2.0/mlflow/runs/get?run_id={latest['run_id']}")["run"] if latest.get("run_id") else {}
    write("ml_renewal_model.json", {
        "model": model.get("full_name"), "latest_version": latest.get("version"), "status": latest.get("status"),
        "metrics": {m["key"]: m["value"] for m in run.get("data", {}).get("metrics", [])},
        "params": {p["key"]: p["value"] for p in run.get("data", {}).get("params", [])},
        "scores_by_fund": ws.sql(f"""SELECT fund_id, count(*) AS leases, round(avg(renewal_probability), 3) AS avg_renewal_probability,
                                            round(sum(expected_vacancy_loss) FILTER (WHERE months_to_expiry <= 24)) AS expected_vacancy_loss_24m
                                     FROM {uc}.renewal_scores GROUP BY fund_id ORDER BY fund_id"""),
        "top_risk_leases": ws.sql(f"""SELECT lease_id, tenant_name, msa, lease_end, round(annual_base_rent) AS abr,
                                             renewal_probability, round(expected_vacancy_loss) AS expected_vacancy_loss
                                      FROM {uc}.renewal_scores WHERE months_to_expiry <= 24
                                      ORDER BY expected_vacancy_loss DESC LIMIT 5"""),
    })

    # ── Lakebase ────────────────────────────────────────────────────────────────
    inst = ws.api("get", "/api/2.0/database/instances/granite-cre")
    synced = {}
    for t in ("property_360", "lease_abstract", "lease_discrepancies", "renewal_scores"):
        st = ws.api("get", f"/api/2.0/database/synced_tables/{uc}.{t}_synced")
        synced[t] = {"state": st.get("data_synchronization_status", {}).get("detailed_state"),
                     "source": st.get("spec", {}).get("source_table_full_name"),
                     "policy": st.get("spec", {}).get("scheduling_policy")}
    write("lakebase_serving.json", {
        "instance": {k: inst.get(k) for k in ("name", "state", "capacity", "pg_version")},
        "synced_tables": synced,
        "corrections_copied_to_delta": ws.sql(f"SELECT * FROM {uc}.abstract_review ORDER BY reviewed_at DESC LIMIT 10"),
        "corrections_applied_in_gold": ws.sql(f"""SELECT lease_id, tenant_name, lease_end, review_status, corrected_fields
                                                  FROM {uc}.lease_abstract WHERE review_status = 'corrected' ORDER BY lease_id"""),
    })

    # ── Genie ───────────────────────────────────────────────────────────────────
    report = ws.sql(f"""SELECT * FROM read_files('/Volumes/{a.catalog}/{a.schema}/artifacts/evidence/genie_benchmarks.json',
                                                 format => 'json', multiLine => true)""")
    if report:
        write("genie_benchmarks.json", json.loads(json.dumps(report[0], default=str)))

    # ── Databricks App ──────────────────────────────────────────────────────────
    try:
        app = ws.cli("apps", "get", a.app_name)
        deployments = ws.cli("apps", "list-deployments", a.app_name)
        deployments = deployments if isinstance(deployments, list) else deployments.get("app_deployments", [])
        write("databricks_app_status.json", {
            "app": {k: app.get(k) for k in ("name", "description", "compute_status", "app_status", "resources",
                                             "user_api_scopes")},
            "latest_deployment": {k: (deployments[0] if deployments else {}).get(k)
                                  for k in ("deployment_id", "status", "create_time", "mode")},
        })
    except RuntimeError as e:
        print(f"app not deployed yet: {e}")


if __name__ == "__main__":
    main()
