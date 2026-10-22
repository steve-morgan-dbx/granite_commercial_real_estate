"""Structure tests for this public end-to-end build.

Adapted from a private demo-generator template for a PUBLIC repo: it contains no
customer markers. Customer-identifying terms are read at run time from the local,
untracked `.scrub_terms` file (see CLAUDE.md). All per-build values come from demo.yml.

Run:  python -m pytest tests -q -p no:cacheprovider
"""
import json
import pathlib
import re

import pytest
import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent

REQUIRED_FILES = ["demo.yml", "README.md", "DEMO.md", "CLAUDE.md", "docs/PLAN.md",
                  ".gitignore", "scripts/scrub_check.sh", "tests/test_structure.py"]
REQUIRED_MANIFEST_KEYS = ["customer", "demo_name", "title", "industry", "problem", "cloud",
                          "catalog", "schema", "deploy", "status", "entry_notebook",
                          "databricks_features", "created"]
# Every stage of the end-to-end journey must be declared.
REQUIRED_STAGES = {"lakeflow", "unity_catalog", "lakebase", "genie", "databricks_app"}
INTELLIGENCE_STAGES = {"ml", "genai"}  # at least one
DEPLOY_METHODS = {"dab", "notebook", "app", "script"}
STATUSES = ["scaffold", "built", "submitted"]
REQUIRED_DEMO_SECTIONS = ["Overview", "The Problem", "Architecture",
                          "Key Databricks Features", "Demo Flow", "Catalog / Schema"]
README_SECTIONS = ["Deploy", "Run Tests"]
TEXT_EXT = {".md", ".py", ".sql", ".yml", ".yaml", ".json", ".ipynb", ".txt", ".toml",
            ".sh", ".tf", ".js", ".ts", ".tsx", ".html", ".css", ".csv"}
# internal/ and .scrub_terms are local-only (gitignored) and are never scanned or published.
SKIP_DIRS = {".git", ".venv", "node_modules", "__pycache__", ".pytest_cache", ".databricks",
             "internal", ".ipynb_checkpoints"}
SKIP_FILES = {".scrub_terms"}
AZURE_ONLY = [r"\babfss://", r"\bwasbs?://", r"\bStandard_[A-Z]\d+"]
SECRET_PATTERNS = [r"dapi[0-9a-f]{32}", r"dose[0-9a-f]{32}", r"AKIA[0-9A-Z]{16}",
                   r"gh[pousr]_[A-Za-z0-9]{36}", r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
                   r"(?i)(password|secret|token)\s*[:=]\s*['\"][^'\"\s{}$]{8,}['\"]"]
INTERNAL_PATTERNS = [r"docs\.google\.com", r"drive\.google\.com", r"[a-z0-9-]+\.atlassian\.net",
                     r"[a-z0-9-]+\.slack\.com", r"github\.com/databricks-field-eng",
                     r"[a-z0-9-]+\.cloud\.databricks\.com", r"[a-z0-9-]+\.azuredatabricks\.net",
                     r"@databricks\.com", r"/Workspace/Users/"]


def _files():
    for p in ROOT.rglob("*"):
        rel = p.relative_to(ROOT)
        if p.is_file() and not (set(rel.parts) & SKIP_DIRS) and p.name not in SKIP_FILES:
            yield p


def _text_files():
    # This file holds the patterns being searched for; exclude it (and the scrub script).
    me = pathlib.Path(__file__).resolve()
    for p in _files():
        if (p.suffix.lower() in TEXT_EXT and p.resolve() != me
                and p.relative_to(ROOT).as_posix() != "scripts/scrub_check.sh"):
            yield p


def _read(p):
    return p.read_text(encoding="utf-8", errors="ignore")


def _headings(md_text):
    return {m.group(1).strip().lower() for m in re.finditer(r"^#{1,3}\s+(.+?)\s*$", md_text, re.M)}


def _code_sources(nb):
    return ["".join(c.get("source", [])) for c in nb.get("cells", []) if c.get("cell_type") == "code"]


def _notebooks():
    return [p for p in _files() if p.suffix == ".ipynb"]


@pytest.fixture(scope="session")
def manifest():
    path = ROOT / "demo.yml"
    assert path.exists(), "demo.yml manifest is missing"
    data = yaml.safe_load(_read(path))
    assert isinstance(data, dict), "demo.yml must be a YAML mapping"
    return data


@pytest.fixture(scope="session")
def stage(manifest):
    return STATUSES.index(manifest.get("status", "scaffold"))


def _require(stage, at_least):
    if stage < STATUSES.index(at_least):
        pytest.skip(f"applies once status >= {at_least}")


# ---------- layout & manifest ----------

@pytest.mark.parametrize("rel", REQUIRED_FILES)
def test_required_file_exists(rel):
    assert (ROOT / rel).is_file(), f"missing required file: {rel}"


def test_manifest_has_required_keys(manifest):
    missing = [k for k in REQUIRED_MANIFEST_KEYS if manifest.get(k) in (None, "", [])]
    assert not missing, f"demo.yml missing/empty keys: {missing}"


def test_manifest_is_generic(manifest):
    assert manifest["customer"] == "generic", "public build: customer must be 'generic'"


def test_status_valid(manifest):
    assert manifest["status"] in STATUSES


def test_demo_name_matches_folder(manifest):
    assert manifest["demo_name"] == ROOT.name
    assert re.fullmatch(r"[a-z][a-z0-9_]*", ROOT.name), "repo folder must be snake_case"


def test_cloud_is_aws(manifest):
    assert str(manifest["cloud"]).lower() == "aws"


def test_deploy_method_valid(manifest):
    assert manifest["deploy"] in DEPLOY_METHODS, f"deploy must be one of {sorted(DEPLOY_METHODS)}"


def test_all_journey_stages_declared(manifest):
    feats = set(manifest["databricks_features"])
    missing = REQUIRED_STAGES - feats
    assert not missing, f"databricks_features missing journey stages: {sorted(missing)}"
    assert feats & INTELLIGENCE_STAGES, "declare at least one of: ml, genai"


# ---------- docs ----------

def test_demo_md_sections():
    heads = _headings(_read(ROOT / "DEMO.md"))
    missing = [s for s in REQUIRED_DEMO_SECTIONS if s.lower() not in heads]
    assert not missing, f"DEMO.md missing sections: {missing}"


def test_demo_md_mentions_catalog_schema(manifest):
    text = _read(ROOT / "DEMO.md")
    for key in ("catalog", "schema"):
        assert str(manifest[key]) in text, f"DEMO.md must mention {key} '{manifest[key]}'"


def test_readme_sections():
    heads = _headings(_read(ROOT / "README.md"))
    missing = [s for s in README_SECTIONS if s.lower() not in heads]
    assert not missing, f"README.md missing sections: {missing}"


# ---------- notebooks ----------

def test_entry_notebook(manifest):
    p = ROOT / manifest["entry_notebook"]
    assert p.suffix == ".ipynb" and p.is_file(), f"entry notebook not found: {manifest['entry_notebook']}"
    nb = json.loads(_read(p))
    first = nb["cells"][0]
    assert first["cell_type"] == "markdown" and "".join(first["source"]).lstrip().startswith("#"), \
        "entry notebook must open with a markdown title cell"
    code = "\n".join(_code_sources(nb))
    for w in ("catalog", "schema"):
        assert re.search(rf"dbutils\.widgets\.\w+\(\s*['\"]{w}['\"]", code), f"entry notebook needs a '{w}' widget"


def test_all_ipynb_valid():
    bad = []
    for p in _notebooks():
        try:
            nb = json.loads(_read(p))
            assert nb.get("nbformat") == 4 and nb.get("cells")
        except Exception as e:  # noqa: BLE001
            bad.append(f"{p.relative_to(ROOT)}: {e!r}")
    assert not bad, f"invalid notebooks: {bad}"


def test_no_py_databricks_notebooks():
    offenders = [str(p.relative_to(ROOT)) for p in _files()
                 if p.suffix == ".py" and _read(p).startswith("# Databricks notebook source")]
    assert not offenders, f"notebooks must be .ipynb, not .py source format: {offenders}"


# ---------- publishing rule (public repo) ----------

def test_gitignore_protects_internal():
    lines = {l.strip() for l in _read(ROOT / ".gitignore").splitlines()}
    for entry in ("internal/", ".scrub_terms", "*.internal.*"):
        assert entry in lines, f".gitignore must contain '{entry}'"


def test_no_secrets():
    hits = [(str(p.relative_to(ROOT)), pat) for p in _text_files() for pat in SECRET_PATTERNS
            if re.search(pat, _read(p))]
    assert not hits, f"possible hard-coded secrets: {hits}"


def test_no_internal_links_or_hosts():
    hits = [(str(p.relative_to(ROOT)), pat) for p in _text_files() for pat in INTERNAL_PATTERNS
            if re.search(pat, _read(p), re.I)]
    assert not hits, f"internal links/hosts/emails/paths found: {hits}"


def test_no_customer_terms():
    terms_file = ROOT / ".scrub_terms"
    if not terms_file.is_file():
        pytest.skip(".scrub_terms not present (local-only file)")
    terms = [t.strip() for t in _read(terms_file).splitlines() if t.strip()]
    hits = [(str(p.relative_to(ROOT)), i) for p in _text_files() for i, t in enumerate(terms)
            if re.search(t, _read(p), re.I)]
    # Report the term's line number in .scrub_terms, never the term itself.
    assert not hits, f"customer-identifying terms found (file, .scrub_terms line index): {hits}"


def test_cloud_specific_resources():
    hits = [(str(p.relative_to(ROOT)), pat) for p in _text_files() for pat in AZURE_ONLY
            if re.search(pat, _read(p))]
    assert not hits, f"Azure-only resources in an AWS build: {hits}"


# ---------- execution evidence (text-readable) ----------

def test_notebooks_committed_with_outputs(stage):
    _require(stage, "built")
    nbs = [p for p in _notebooks() if p.parts[len(ROOT.parts)] == "notebooks"]
    assert nbs, "no notebooks/ found"
    empty = [str(p.relative_to(ROOT)) for p in nbs
             if not any(c.get("outputs") for c in json.loads(_read(p))["cells"] if c.get("cell_type") == "code")]
    assert not empty, f"notebooks without outputs (execution evidence): {empty}"


def test_evidence_files_present(stage):
    _require(stage, "built")
    ev = ROOT / "evidence"
    files = [p for p in ev.rglob("*") if p.is_file() and p.suffix in {".json", ".csv", ".txt", ".md", ".log"}] if ev.is_dir() else []
    assert files, "evidence/ must contain text-readable run output"


def test_evidence_covers_every_stage(manifest, stage):
    _require(stage, "built")
    names = " ".join(p.as_posix().lower() for p in (ROOT / "evidence").rglob("*") if p.is_file())
    for s in sorted(REQUIRED_STAGES) + [sorted(set(manifest["databricks_features"]) & INTELLIGENCE_STAGES)[0]]:
        assert s in names, f"evidence/ has no file for stage '{s}' (name files by stage)"


def test_deck_present(stage):
    _require(stage, "built")
    deck = [p for p in (ROOT / "deck").glob("*") if p.suffix in {".md", ".pdf", ".txt"}] if (ROOT / "deck").is_dir() else []
    assert deck, "deck/ must contain the business presentation (.md/.pdf/.txt)"


# ---------- deployment ----------

def test_bundle_config(manifest, stage):
    if manifest["deploy"] != "dab":
        pytest.skip("not a bundle build")
    path = ROOT / "databricks.yml"
    if not path.is_file():
        _require(stage, "built")
    assert path.is_file(), "deploy: dab requires databricks.yml"
    cfg = yaml.safe_load(_read(path))
    assert cfg.get("bundle", {}).get("name"), "databricks.yml must set bundle.name"
    assert "dev" in (cfg.get("targets") or {}), "databricks.yml must define a 'dev' target"
