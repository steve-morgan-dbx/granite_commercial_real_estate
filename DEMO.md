# Granite Peak CRE Portfolio Intelligence

## Overview
An end-to-end Databricks build for **Granite Peak Real Estate Partners**, a fictional commercial real estate investment manager with ~120 office, retail and industrial assets. It turns lease PDFs, ERP change data and public map data into governed, H3-indexed portfolio intelligence. The investment team queries it in Genie, and asset managers act on it in a Databricks App. The audience is the Head of Transactions (executive sponsor) and the Asset Management / BI lead (domain owner). Full design: [`docs/PLAN.md`](docs/PLAN.md).

## The Problem
Lease rollover and renewal risk can't be measured across the portfolio. The clauses that drive it (renewal options, co-tenancy, termination rights, escalations, exclusives) exist only in lease documents. The rent roll lives in the property-management ERP. Neighborhood context (competing supply, POI density) isn't joined to either. Abstraction is manual (3–6 hours per lease), discrepancies between leases and the ERP surface only in audits or due diligence, and rollover reporting is quarterly and built by hand.

## Architecture
```
Synthetic ERP CDC files ─┐
Synthetic lease + deal PDFs ─┤ Lakeflow pipeline (bronze → silver → gold)
Overture Maps (public) ─┘   ai_parse_document → ai_extract → lease/deal abstracts; H3 on every asset/POI
          │
Unity Catalog: volumes, tags, masks, fund row filter, lineage, metric view, trusted H3 functions
          │
  ├─ ML: renewal-propensity model (MLflow, UC registry) → gold.renewal_scores
  ├─ Lakebase: synced property_360 / lease_abstract / renewal_scores + abstract_review writeback
  ├─ Genie: gold + metric view + H3 functions, validated benchmarks
  └─ Databricks App: H3 portfolio map, property 360, document review queue, embedded Genie
```

## Key Databricks Features
1. Lakeflow Spark Declarative Pipelines - Auto Loader ingest of CDC files, PDFs and GeoParquet; AUTO CDC to SCD2 dimensions
2. AI Functions (`ai_parse_document`, `ai_extract`) - lease and deal abstraction inside the pipeline, scored against generator ground truth
3. Native H3 + spatial SQL - competitor density, k-ring proximity, neighborhood rollups
4. Unity Catalog - tags, column masks, a fund row filter, lineage from PDF to Genie answer, a metric view
5. MLflow + UC model registry - tenant renewal-propensity model, batch-scored into gold
6. Lakebase - low-latency serving for the app, with analyst corrections merged back to gold
7. Genie - natural-language portfolio analytics combining document-derived fields with H3 context
8. Databricks Apps - the business surface for asset managers

## Demo Flow
1. Setup: deploy with Declarative Automation Bundles (`databricks.yml`, `dev` target), or run `notebooks/00_setup.ipynb` and the numbered notebooks in order.
2. Act 1 - Documents become data: a lease PDF becomes an abstract with confidence scores, discrepancies with the ERP are flagged, and lineage shows the path.
3. Act 2 - Ask Genie: rollover, co-tenancy and competitor density in one question; the same question returns different rows for users in different funds.
4. Act 3 - Act on it: in the app, review a low-confidence abstract next to its PDF and correct it; the fix flows through Lakebase to gold and Genie.
5. Act 4 - Predict: renewal probability × ABR at risk gives expected vacancy loss by asset and fund.

## Catalog / Schema
- Catalog: `smmorgan_catalog` (default; override with the `catalog` widget or bundle variable)
- Schema: `granite_commercial_real_estate`
