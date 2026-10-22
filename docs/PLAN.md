# Granite Peak CRE Portfolio Intelligence — Build Plan

An end-to-end Databricks prototype for a fictional commercial real estate (CRE) investment manager, **Granite Peak Real Estate Partners**. All data is synthetic or public open data.

## 1. The problem

> *A CRE investment manager's lease terms are trapped in PDFs, its rent roll lives in its property-management ERP, and its market context lives nowhere. We unify all three on Databricks, H3-index every asset, and let the investment team ask Genie questions like **"Which retail assets have >25% of rent rolling in the next 24 months, a co-tenancy clause, and rising competitor density within 1 km?"***

- **Industry:** commercial real estate investment management (REITs, real-asset managers).
- **Specific problem:** lease rollover and renewal risk can't be measured at the portfolio level, because the clauses that drive it (renewal options, co-tenancy, termination rights, escalations, exclusives) exist only in lease documents. The neighborhood context that predicts renewal (competing supply, amenity/POI density) isn't joined to the rent roll either.
- **Company:** Granite Peak Real Estate Partners: ~120 assets across office, retail, industrial and multifamily in about 8 Western / Mountain-West MSAs, plus an active acquisitions pipeline.
- **Personas:**
  - *Executive sponsor*, Head of Transactions: faster, better-informed buy/sell/hold decisions.
  - *Domain owner*, Asset Management / BI lead: self-service analytics and usable document data.

## 2. Business KPIs

| KPI | Baseline (stated assumption) | With the solution |
|---|---|---|
| Lease abstraction time | 3–6 hrs/lease, manual or outsourced (~$150–400/lease) | Minutes, with human review of low-confidence fields |
| Abstract ↔ ERP discrepancies found | Unknown; surfaced during audits or deal due diligence | Flagged automatically (rent, expiration, option dates) |
| Rollover visibility (% ABR rolling ≤24 mo, WALT) | Quarterly, built by hand in BI | Daily; ask anything in Genie |
| Deal-screening cycle time | Days to pull comps, lease terms and location context | Minutes, in one Genie or App session |
| Expected vacancy loss ($) | Not quantified | Renewal probability × ABR at risk, by asset and fund |

## 3. Why Databricks

Individual features (an H3 function, a document parser, a chat-with-data tool) exist in many products. The differentiator this build demonstrates is **integration**:

> **Structured ERP data, unstructured lease and deal documents, geospatial context, ML models, natural-language analytics, an operational database and the business app all run on one open, governed copy of the data, with one security model (Unity Catalog), one lineage graph, and no data copied between tools.**

| # | Pillar | Proof in this build | Public customer evidence |
|---|---|---|---|
| 1 | **Unstructured documents are governed data.** PDFs live in UC volumes; `ai_parse_document` + `ai_extract` run inside the Lakeflow pipeline and inherit lineage, tags and masks | Lineage: lease PDF → parsed text → abstract → Genie answer → app | [First American](https://www.databricks.com/customers/fadna): 100+ fields extracted from ~4M historical title-policy images (from an 8B+ document repository); 70% lower cost, 75% less project time, 10× more data elements |
| 2 | **ML lives in the same pipeline as the data.** MLflow + the UC model registry sit next to the gold tables | Renewal model trained on document-derived clauses + ERP history + H3 features, batch-scored into gold | [Reonomy](https://www.databricks.com/customers/reonomy): 3× faster ML lifecycle; model to production in <2 months (previously 6). [Xanadu](https://www.databricks.com/customers/xanadu-realty): Feature Store + MLflow on unified data with Power BI on top; +25% lead-to-customer conversion |
| 3 | **Geospatial is native SQL at lakehouse scale**, and Genie can use it | Genie: "assets within ~2 km of deal GP-ACQ-014" via an `h3_kring` trusted function; neighborhood rollups with `h3_coverash3` + `st_covers` | [Geospatial GenAI for Real Estate Investment](https://community.databricks.com/t5/technical-blog/customer-smarter-maps-smarter-markets-geospatial-genai-for-real/ba-p/127677): H3 + spatial SQL + Vector Search + Foundation Model APIs in one workflow; 95% runtime reduction using H3 distance approximation |
| 4 | **Natural-language analytics runs on the same governance.** Genie respects UC row filters and masks, sits on metric views, and shows its SQL | The same Genie question returns different rows for users in different funds (row filter); "Show SQL" | [JLL](https://www.databricks.com/customers/jll/training-and-certification): built JLL Azara, its CRE data and insights platform, on Databricks SQL + Delta; 60% less ETL processing time |
| 5 | **The operational app and its database are part of the platform.** Lakebase (Postgres) is synced from gold; the app writes corrections back with no reverse-ETL tool | An analyst fixes a mis-extracted renewal date → Lakebase → gold → Genie sees the fix | (demonstrated in this build) |
| 6 | **Third-party data arrives by open sharing, not copies** (Delta Sharing / Marketplace) | A documented `neighborhood_enrichment` contract where licensed data (e.g., ATTOM, Cotality Marketplace listings) plugs in | ATTOM and Cotality publish CRE/property data on Databricks Marketplace |

## 4. Data sources

| Source | Type | Use |
|---|---|---|
| **Synthetic ERP extracts** shaped like Yardi Voyager (`property`, `unit`, `tenant`, `commlease`, `lease_charges`, `gl_actuals`) | Generated | Landed as **CDC files in the style of Qlik Replicate** (`header__operation`, `header__timestamp`), which is a common CRE ingest pattern |
| **Synthetic deal pipeline** (`deal`, `deal_comps`) | Generated | Acquisitions/dispositions: stage, property type, market, ask price, cap rate, IRR, lat/lon |
| **Synthetic deal documents** (~10–15 offering memoranda + rent rolls) | Generated PDFs | Extract asking price, NOI, WALT, tenant list, and the renewal/co-tenancy terms of in-place leases |
| **Synthetic commercial lease PDFs** (~60–100) | Generated PDFs + ground-truth JSON | Lease abstraction. Clauses vary on purpose, and ~10% deliberately disagree with the ERP to drive discrepancy detection |
| **Overture Maps: Places, Buildings, Divisions** | Public open data, ingested by Lakeflow | POI and competitor density, building footprints, neighborhood/submarket polygons. Downloaded by bounding box for the Granite Peak MSAs → UC volume → Auto Loader |
| **ATTOM / Cotality** | Databricks Marketplace (licensed) | Not included. Shown as the day-2 enrichment plug-in via Delta Sharing |

## 5. Architecture

```
Volume /landing/erp_cdc/*.json    ─┐
Volume /landing/docs/*.pdf        ─┤  LAKEFLOW (Spark Declarative Pipeline, serverless)
Overture (public, bbox download)  ─┘   bronze: Auto Loader (CDC files, PDFs as binary, GeoParquet)
                                       silver: AUTO CDC → SCD2 dims (property, lease, tenant)
                                               ai_parse_document → document text
                                               ai_extract / ai_query → lease_abstract, deal_abstract (+ confidence)
                                               h3_longlatash3(lon, lat, 9) on properties, deals, POIs
                                       gold:   rent_roll, rollover_schedule, lease_discrepancies,
                                               h3_market_context (POI/competitor density, k-rings,
                                               submarket polygons), portfolio metric view
                                               (ABR, WALT, occupancy, NOI)
        │
UNITY CATALOG  volumes, tags (PII on tenant contacts), column masks, row filter by fund,
               column comments, lineage across tables, models, functions and the Genie space
        │
ML / GenAI     (a) GenAI document abstraction, evaluated field-by-field against generator ground truth
               (b) tenant renewal-propensity model (MLflow, UC-registered); features = document-derived
                   lease terms + ERP payment history + H3 neighborhood → expected_vacancy_loss
        │
LAKEBASE       synced tables (property_360, lease_abstract, renewal_scores) for low-latency app reads
               + native Postgres table abstract_review (analyst corrections, written by the app)
        │
GENIE          space over gold + metric view; H3 UC functions as trusted assets; benchmark questions
        │
DATABRICKS APP H3 hex map of portfolio + market context, property 360 (Lakebase),
               document review queue with source PDF + writeback, embedded Genie chat
```

Everything is deployed with a **Databricks Asset Bundle** (pipeline, jobs, model training, Genie setup, app, Lakebase sync).

## 6. Signature moment: H3 + document parsing in Genie

Genie joins **document-derived columns** with **H3 spatial context** in a single natural-language question.

- `gold.lease_abstract`: `has_co_tenancy`, `renewal_option_count`, `termination_right_date`, `escalation_type`, `exclusive_use`, `abstract_confidence`, …
- `gold.property_h3`: `h3_res9`, `h3_res7`, MSA, submarket
- `gold.h3_market_context`: per-hex POI counts by category, competitor counts, building density
- **Trusted UC functions for Genie:** `competitors_within(property_id, k_ring, category)`, `assets_near(lon, lat, k_ring)`
- **Genie instructions:**
  - Longitude comes before latitude.
  - `h3_kring` measures grid distance (a res-9 cell edge is about 175 m, so k=3 is roughly 1 km).
  - For exact polygon membership, use `h3_coverash3` candidate cells, then `st_covers`.
  - Synonyms: ABR = annualized base rent, plus region names.
  - Measures come from the metric view.
- **Benchmark questions** (each with validated SQL):
  1. Show acquisitions in the pipeline over $50M by property type and market.
  2. Which held assets have >20% of rent rolling in the next 24 months?
  3. Compare occupancy this year vs. last year by region. (follow-up context)
  4. Which retail assets have >25% of ABR expiring within 24 months and a co-tenancy clause?
  5. For leases expiring in 2027, how many competing retail POIs are within ~1 km of each property?
  6. Show leases where the abstracted expiration date disagrees with the ERP.
  7. What's the WALT by fund and MSA?
  8. Which tenants with termination rights in the next 18 months have renewal probability below 40%?
  9. For deal GP-ACQ-014, which held assets are within ~2 km, and what's their occupancy?
  10. What renewal options and co-tenancy clauses appear across the in-place leases in deal GP-ACQ-014's offering memorandum?
  11. How many assets, and how much ABR, are in each Salt Lake City neighborhood?

## 7. Execution evidence

The build is validated from text artifacts committed to this repo:
- `notebooks/*.ipynb` committed **with outputs**: data generation, pipeline validation, ML training, Lakebase checks, Genie API calls
- `evidence/`: pipeline update JSON, job run output, query result samples (CSV/JSON), MLflow metrics, Genie question → SQL → result JSON, benchmark accuracy, extraction accuracy vs. ground truth, app API responses, Lakebase query output
- `README.md` mapping each stage (Lakeflow → Unity Catalog → Lakebase → ML/GenAI → Genie → App) to its code and evidence files
- `scripts/scrub_check.sh` runs as a pre-push hook so nothing sensitive is published

## 8. Repository layout (planned)

```
granite_commercial_real_estate/
├── README.md
├── databricks.yml            # Asset Bundle
├── resources/                # pipeline, jobs, app, Lakebase sync, Genie setup
├── src/
│   ├── datagen/              # ERP CDC generator, lease + deal PDF generators (+ ground truth)
│   ├── pipeline/             # bronze / silver / gold, document intelligence, H3 context
│   ├── governance/           # tags, masks, row filters, comments, metric view
│   ├── ml/                   # renewal model
│   ├── lakebase/             # synced tables, abstract_review DDL, grants
│   └── genie/                # space config, instructions, trusted functions, benchmarks
├── app/                      # Databricks App
├── notebooks/                # evidence notebooks (.ipynb with outputs)
├── evidence/                 # run output, query results, Genie transcripts, scores
├── deck/                     # business presentation (.md + PDF)
├── docs/                     # this plan
└── scripts/                  # scrub check + hook installer
```

## 9. Schedule

| When | Work |
|---|---|
| Thu 10/22 | Workspace checks, repo scaffold, this plan |
| Fri 10/23 | Synthetic ERP CDC + document generators → volume; Overture ingest; bronze/silver pipeline |
| Mon 10/26 | Gold + H3 market context + metric view; governance; renewal model; Lakebase; Genie space + benchmarks |
| Tue 10/27 | Databricks App; evidence capture; presentation deck |
| Thu 10/29–Fri 10/30 | Final evidence pass and README stage map |

**Cut line:** if time runs short, the app keeps the map + Genie chat and drops the writeback, and the renewal model becomes a scored rule set logged to MLflow. Genie + H3 + document abstraction are never cut.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Genie accuracy on spatial questions | Trusted UC functions for H3 logic, a metric view, validated benchmarks, explicit instructions |
| Extraction quality on synthetic PDFs | The generator emits ground truth, so field-level accuracy is measured and committed |
| Overture download blocked from serverless | Download the bounding-box extract locally, upload to the volume, and ingest with Lakeflow as usual |
| Lakebase permissions for the app | Grant the app service principal's Postgres role directly; UC grants on synced tables don't authorize Postgres reads |
