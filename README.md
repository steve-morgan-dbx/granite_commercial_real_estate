# granite_commercial_real_estate

A fictional commercial real estate (CRE) demo that shows Databricks end to end, with an emphasis on Genie.

**Granite Peak Real Estate Partners** is a fictional CRE investment manager. Its lease terms are trapped in PDFs, its rent roll lives in its property-management ERP, and its market context lives nowhere. This build brings all three together on Databricks:

| Stage | What it does here |
|---|---|
| **Lakeflow** | Ingests synthetic ERP change-data-capture files, lease and deal PDFs, and public Overture Maps data |
| **Unity Catalog** | Governs tables, volumes, models, functions and the Genie space (tags, masks, row filters, lineage) |
| **ML / GenAI** | `ai_parse_document` + `ai_extract` lease and deal abstraction; tenant renewal-propensity model in MLflow |
| **Lakebase** | Low-latency property and lease serving for the app, plus analyst corrections written back |
| **Genie** | Natural-language portfolio analytics that combines document-derived fields with H3 geospatial context |
| **Databricks App** | Portfolio map, property 360, document review queue, embedded Genie chat |

All data is synthetic or public open data.

- Plan: [`docs/PLAN.md`](docs/PLAN.md)
- Status: scaffold only. Code, notebooks and execution evidence will follow.

## Development

This repo is public. Read [`CLAUDE.md`](CLAUDE.md) before contributing: nothing internal is published, and non-public material stays in the gitignored `internal/` folder.

Install the pre-push scrub check once per clone:

```bash
scripts/install_hooks.sh
```
