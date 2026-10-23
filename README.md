# granite_commercial_real_estate

A fictional commercial real estate (CRE) build that runs end to end on Databricks, with an emphasis on Genie.

**Granite Peak Real Estate Partners** is a fictional CRE investment manager: 118 office, retail and industrial assets in eight Western US metros, about $370M of annualized base rent and an active acquisitions pipeline. Its lease terms are trapped in PDFs, its rent roll lives in its property-management ERP, and its market context lives nowhere. This build brings the three together on one governed platform, so the investment team can ask Genie questions like:

> *"Which retail assets have more than 25% of ABR expiring within 24 months and a co-tenancy clause?"*
> *"For deal GP-ACQ-014, which held assets are within about 2 km, and what's their occupancy?"*

All data is synthetic, except Overture Maps open data (CDLA Permissive 2.0 / ODbL).

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
# then enable the app (resources/app.yml.pending → resources/app.yml) and deploy it:
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
