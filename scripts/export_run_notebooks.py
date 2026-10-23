"""Copy executed outputs from a Databricks job run into the repo's .ipynb notebooks.

Execution evidence must be readable as text, so notebooks are committed with their outputs. This script exports each
notebook task of a job run, converts every command result (print output, display() tables, errors) into
standard Jupyter outputs, scrubs workspace hostnames, emails and user paths, and writes them into the matching
notebook under notebooks/ (matched by file name). It also writes a run summary to evidence/.

Usage:  python3 scripts/export_run_notebooks.py <job_run_id> --profile <cli-profile>
"""
import argparse
import base64
import datetime
import json
import pathlib
import re
import subprocess
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAX_TABLE_ROWS = 25

SCRUB = [
    (re.compile(r"https?://[a-z0-9.-]+\.(cloud\.databricks\.com|azuredatabricks\.net|gcp\.databricks\.com)[^\s'\"]*", re.I), "<workspace-url>"),
    (re.compile(r"[a-z0-9-]+\.(cloud\.databricks\.com|azuredatabricks\.net)", re.I), "<workspace-host>"),
    (re.compile(r"/Workspace/Users/[^/\s'\"]+"), "<user-workspace>"),
    (re.compile(r"/Users/[^/\s'\"]+@[^/\s'\"]+"), "/Users/<user>"),
    (re.compile(r"[A-Za-z0-9._%+-]+@databricks\.com"), "<user>"),
    (re.compile(r"\x1b\[[0-9;]*m"), ""),  # ANSI colors in tracebacks
]


def scrub(text):
    for pattern, repl in SCRUB:
        text = pattern.sub(repl, text)
    return text


def cli(args, profile):
    out = subprocess.run(["databricks", *args, "-p", profile, "-o", "json"], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def notebook_model(html):
    """Decode the notebook model embedded in an exported run view."""
    m = re.search(r"__DATABRICKS_NOTEBOOK_MODEL = '([^']+)'", html)
    if not m:
        raise ValueError("no notebook model in export")
    return json.loads(urllib.parse.unquote(base64.b64decode(m.group(1)).decode("utf-8")))


def _table_text(result):
    schema = [c.get("name", "") for c in result.get("schema", [])]
    rows = result.get("data", [])[:MAX_TABLE_ROWS]
    cells = [schema] + [["" if v is None else str(v) for v in r] for r in rows]
    widths = [max(len(r[i]) for r in cells) for i in range(len(schema))]
    lines = [" | ".join(v.ljust(widths[i]) for i, v in enumerate(r)) for r in cells]
    lines.insert(1, "-+-".join("-" * w for w in widths))
    total = len(result.get("data", []))
    if total > MAX_TABLE_ROWS:
        lines.append(f"... {total - MAX_TABLE_ROWS} more rows")
    return "\n".join(lines) + "\n"


def _outputs(result):
    if not result:
        return []
    kind = result.get("type")
    if kind == "listResults":
        return [o for r in result.get("data", []) for o in _outputs(r)]
    if kind == "table":
        return [{"output_type": "stream", "name": "stdout", "text": scrub(_table_text(result))}]
    if kind in ("text", "html", "ansi"):
        data = result.get("data") or ""
        if kind == "html":
            data = re.sub(r"<[^>]+>", "", data)
        return [{"output_type": "stream", "name": "stdout", "text": scrub(str(data))}] if str(data).strip() else []
    if kind == "error":
        cause = scrub(result.get("cause") or result.get("summary") or "error")
        return [{"output_type": "error", "ename": "Error", "evalue": cause.splitlines()[0][:300],
                 "traceback": cause.splitlines()[:40]}]
    data = result.get("data")
    return [{"output_type": "stream", "name": "stdout", "text": scrub(json.dumps(data, default=str)[:4000])}] if data else []


def apply(nb_path, model):
    nb = json.loads(nb_path.read_text())
    commands = sorted(model.get("commands", []), key=lambda c: c.get("position", 0))
    if len(commands) != len(nb["cells"]):
        raise ValueError(f"{nb_path.name}: {len(commands)} commands vs {len(nb['cells'])} cells")
    count = 0
    for cell, cmd in zip(nb["cells"], commands):
        if cell["cell_type"] != "code":
            continue
        count += 1
        cell["execution_count"] = count
        cell["outputs"] = _outputs(cmd.get("results"))
    nb_path.write_text(json.dumps(nb, indent=1, ensure_ascii=False))
    return sum(1 for c in nb["cells"] if c.get("outputs"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id")
    ap.add_argument("--profile", required=True)
    args = ap.parse_args()

    run = cli(["jobs", "get-run", args.run_id], args.profile)
    summary = {"job_name": run.get("run_name"), "run_id": run["run_id"],
               "result_state": run["state"].get("result_state"),
               "start_time_utc": datetime.datetime.fromtimestamp(run["start_time"] / 1000, datetime.timezone.utc).isoformat(timespec="seconds"),
               "tasks": []}
    for task in run["tasks"]:
        entry = {"task_key": task["task_key"], "result_state": task["state"].get("result_state"),
                 "duration_s": round((task.get("execution_duration") or 0) / 1000)}
        nb_task = task.get("notebook_task")
        if nb_task and entry["result_state"] == "SUCCESS":
            export = cli(["jobs", "export-run", str(task["run_id"]), "--views-to-export", "CODE"], args.profile)
            name = pathlib.Path(nb_task["notebook_path"]).name
            target = ROOT / "notebooks" / (name if name.endswith(".ipynb") else name + ".ipynb")
            entry["notebook"] = f"notebooks/{target.name}"
            try:
                entry["cells_with_output"] = apply(target, notebook_model(export["views"][0]["content"]))
            except ValueError as e:  # the notebook changed after this run; re-run before exporting it
                entry["skipped"] = str(e)
                print(f"skipped: {e}")
        summary["tasks"].append(entry)

    ev = ROOT / "evidence"
    ev.mkdir(exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "_", run.get("run_name", "run").lower()).strip("_")
    out = ev / f"job_run_{slug}_{run['run_id']}.json"
    out.write_text(scrub(json.dumps(summary, indent=2)) + "\n")
    print(json.dumps(summary, indent=2))
    print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
