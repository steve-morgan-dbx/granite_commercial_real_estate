# granite_commercial_real_estate

**Outcome: a commercial real estate investment manager can see, price and act on its lease-rollover risk in one governed platform, worth an estimated $1.4M a year on a $370.8M rent roll.**

Granite Peak Real Estate Partners (fictional) owns 118 office, retail and industrial assets in eight Western US metros: 391 leases and $370.8M of annualized base rent (ABR). **$89.8M of that rent (24.2%) rolls in the next 24 months.** The clauses that decide whether those tenants renew (renewal options, co-tenancy, termination rights) are trapped in PDFs. The rent roll lives in the property-management ERP, and nobody checks the two against each other.

What the build delivers, measured on its own run:

| | Result |
|---|---|
| Lease abstraction | 116 lease PDFs and 26 deal documents abstracted inside the data pipeline; 100% field accuracy against the answer key (clean synthetic PDFs) |
| ERP vs. signed lease | 16 mismatched leases flagged automatically, covering $22.4M of ABR and $0.68M a year in rent differences |
| Renewal risk, in dollars | $34.5M of expected vacancy loss over 24 months, lease by lease, from a renewal model in Unity Catalog |
| Self-service | Genie answers 10 of 11 benchmark questions correctly (1 partial), combining lease clauses, ERP data and H3 market context, under fund-level row security |
| Action | Analysts fix flagged abstracts in a Databricks App; corrections go through Lakebase back to the gold tables and Genie |

**Estimated value: ≈ $1.4M a year**, all three assumptions stated:
- **≈ $1.0M a year:** winning back 3 points of renewal rate on the $89.8M expiring. Each point avoids about $0.67M of downtime over 24 months, at 9 months to re-lease.
- **≈ $0.34M a year:** half of the $0.68M a year in rent differences on the 12 rent-mismatched leases resolved in the landlord's favor.
- **≈ $0.06–0.16M per abstraction cycle:** 391 leases at a typical $150–400 per outsourced abstraction; analysts review only the flagged leases.

> *"Which retail assets have more than 25% of ABR expiring within 24 months and a co-tenancy clause?"*
> *"For deal GP-ACQ-014, which held assets are within about 2 km, and what's their occupancy?"*

All data is synthetic, except Overture Maps open data (CDLA Permissive 2.0 / ODbL).

**Read next:** the business deck [`deck/`](deck/) · the demo voice track [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md) · decisions and trade-offs [`docs/DECISIONS.md`](docs/DECISIONS.md) · how AI was used to build it [`docs/BUILT_WITH_AI.md`](docs/BUILT_WITH_AI.md)

## Stage map: code and execution evidence

Every stage below ran in a Databricks workspace. The notebooks are committed **with their outputs**, and `evidence/` holds text output collected from the workspace after the run.

| Stage | What it does here | Code | Evidence |
|---|---|---|---|
| **Lakeflow** | Auto Loader ingests ERP CDC files (Qlik Replicate style), lease and deal PDFs, and Overture GeoParquet; AUTO CDC builds SCD1 dimensions and SCD2 lease history; gold materialized views | `pipelines/transformations/`, `resources/pipeline.yml`, `notebooks/01_*`, `02_*` | `evidence/lakeflow_pipeline_update.json`, `notebooks/01_generate_synthetic_data.ipynb` |
| **Unity Catalog** | Fund row filter on `rent_roll`, `rollover_schedule` and `occupancy_monthly`; column masks on tenant contacts; governed tags; column comments; lineage from PDF to gold | `notebooks/03_governance.ipynb`, `04_semantic_layer.ipynb`, `src/governance/` | `evidence/unity_catalog_governance.json`, `notebooks/04_semantic_layer.ipynb` |
| **GenAI** | `ai_parse_document` + `ai_extract` abstract lease and deal PDFs inside the pipeline; ERP discrepancy detection; accuracy scored against generator ground truth | `pipelines/transformations/silver/documents.sql`, `gold/tables.sql` | `evidence/genai_document_extraction.json` |
| **ML** | Tenant renewal-propensity model (gradient boosting, MLflow, Unity Catalog registry) on ERP, document and H3 features → `renewal_scores` with expected vacancy loss | `notebooks/05_renewal_model.ipynb` | `evidence/ml_renewal_model.json`, `notebooks/05_renewal_model.ipynb` |
| **Lakebase** | Snapshot-synced `property_360`, `lease_abstract`, `lease_discrepancies`, `renewal_scores`; native `app.abstract_review` for analyst corrections, copied back to Delta and applied in gold | `notebooks/06_lakebase.ipynb`, `08_app_permissions.ipynb` | `evidence/lakebase_serving.json`, `notebooks/06_lakebase.ipynb` |
| **Genie** | Space over gold tables, two metric views and three trusted H3 functions, with instructions, example SQL and 11 scored benchmarks | `notebooks/07_genie_space.ipynb`, `src/genie/` | `evidence/genie_benchmarks.json`, `notebooks/07_genie_space.ipynb` |
| **Databricks App** | Streamlit app: H3 portfolio map, property 360 from Lakebase, lease review queue with Lakebase writeback, Genie on behalf of the signed-in user | `app/`, `resources/app.yml` | `evidence/databricks_app_status.json` |

Design and status: [`docs/PLAN.md`](docs/PLAN.md). Demo narrative: [`DEMO.md`](DEMO.md). Business deck: [`deck/`](deck/).

## Deploy

Everything is deployed with a Declarative Automation Bundle (`databricks.yml`, target `dev`). Pass `--profile <your-profile>` to each command.

```bash
databricks bundle deploy --target dev
databricks bundle run granite_ingest_overture   # one time: Overture places, buildings, divisions, division areas
databricks bundle run granite_build             # setup → governance → data → pipeline → semantic layer, model → Lakebase, Genie
# then point the app at your warehouse and the Genie space the build created, and deploy it:
databricks bundle deploy --var warehouse_id=<serverless-warehouse-id> --var genie_space_id=<space-id>
databricks bundle run granite_app
databricks bundle run granite_app_permissions
```

Defaults are catalog `smmorgan_catalog` and schema `granite_commercial_real_estate`; override them with `--var catalog=... --var schema=...`. Requirements: Unity Catalog, serverless compute, a serverless SQL warehouse, AI Functions, Lakebase and Databricks Apps.

## Run Tests

    python -m pytest tests -q -p no:cacheprovider

The structure tests check the layout, the manifest, the publishing rule and, once `demo.yml` has `status: built`, that notebooks carry outputs and that `evidence/` covers every stage.

## Refresh the evidence

```bash
python3 scripts/export_run_notebooks.py <granite_build run id> --profile <profile>   # notebook outputs
python3 scripts/collect_evidence.py --profile <profile> --warehouse <warehouse-id>   # evidence/*.json
```

## Development

This repo is public. Read [`CLAUDE.md`](CLAUDE.md) before contributing: nothing internal is published, and non-public material stays in the gitignored `internal/` folder. Install the pre-push scrub check once per clone:

```bash
scripts/install_hooks.sh
```
