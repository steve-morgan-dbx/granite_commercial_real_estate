# Granite Peak Portfolio Intelligence
### Measuring lease rollover risk across a $370M commercial rent roll, in one governed platform

*Granite Peak Real Estate Partners is fictional; all figures come from the synthetic build in this repository.*

---

## 1. The outcome

**Every lease, every clause, every neighborhood: one question away. Estimated value ≈ $1.4M a year.**

| | Before | After |
|---|---|---|
| Lease abstraction | 3–6 analyst hours per lease, done ad hoc | 116 leases abstracted in about 3 minutes inside the data pipeline |
| ERP vs. lease mismatches | Found in audits or deal due diligence | 16 mismatches flagged automatically, before the next rent bill |
| Rollover visibility | Quarterly spreadsheet | Daily: 24.2% of ABR rolls in 24 months, by fund, market and asset |
| Vacancy risk | Not priced | $34.5M of expected vacancy loss in the next 24 months, by lease |
| Deal screening context | Days of pulling comps, leases and maps | Seconds: "which of our assets are near this deal, and how are they doing?" |

---

## 2. The problem

Granite Peak owns 118 office, retail and industrial assets in eight Western US metros, with 391 active leases and $370.8M of annualized base rent (ABR).

- **The clauses that drive renewal risk live only in PDFs.** Renewal options, co-tenancy, termination rights and exclusives are not in the ERP.
- **The rent roll lives in the ERP.** It's trusted for billing, but it's never reconciled against the signed lease.
- **Market context lives nowhere.** Nobody joins competing supply and amenities around each asset to the rent roll.

So the questions that matter to an investment committee take days, and they're answered from stale extracts.

---

## 3. Who it's for

**Executive sponsor: Head of Transactions**
- Faster, better-informed buy / sell / hold decisions.
- Deal screening in one conversation: pipeline, nearby held assets, their occupancy, and the in-place lease terms from the offering memorandum.
- Rollover and vacancy risk priced in dollars, not described in adjectives.

**Domain owner: Head of Asset Management / BI lead**
- Self-service answers without a report-request queue.
- Document data that is finally usable, with a review queue for the exceptions.
- One security model: each fund team sees only its own funds, everywhere.

---

## 4. Buyer KPIs, measured in the build

| KPI | Result | How it's measured |
|---|---|---|
| Abstraction throughput | 116 leases + 26 deal documents per pipeline run | `evidence/lakeflow_pipeline_update.json` |
| Extraction accuracy | 100% on core terms; 100% on clause flags (116 synthetic, machine-generated PDFs; scanned real leases will score lower, which the pilot measures) | Field-by-field vs. generator ground truth, `evidence/genai_document_extraction.json` |
| Mismatch detection | 11 of 11 planted mismatches caught, plus 5 ERP rent amendments not reflected in the signed lease; $22.4M of ABR sits on flagged leases | Same file |
| Analyst time avoided | ≈ 350–700 hours per abstraction cycle (at 3–6 h/lease); review needed only for flagged leases | Stated assumption × measured volume |
| ABR rolling in 24 months | 24.2% ($89.8M) | `portfolio_metrics` metric view |
| Expected vacancy loss, 24 months | $34.5M | `renewal_scores` (renewal probability × ABR × 9 months downtime) |
| Self-service accuracy | 10 of 11 benchmark questions answered correctly by Genie (the 11th partially) | `evidence/genie_benchmarks.json` |
| Operational latency | 2.8 ms average property lookup from Lakebase | `notebooks/06_lakebase.ipynb` |

---

## 5. The value, in dollars

**≈ $1.4M a year on a $370.8M rent roll (about 0.4% of ABR).** Each line has a stated assumption you can change.

| Lever | Assumption | Value |
|---|---|---|
| Renewals won back | +3 points of renewal rate on the $89.8M of ABR expiring in 24 months; 9 months of downtime avoided per renewal | ≈ $1.0M / year |
| Rent billing corrected | Half of the $0.68M a year in rent differences on 12 rent-mismatched leases resolved in the landlord's favor | ≈ $0.34M / year |
| Abstraction cost avoided | 391 leases × $150–400 per outsourced abstraction; analysts review only flagged leases | ≈ $0.06–0.16M / cycle |

**Sensitivity:** each point of renewal rate on the expiring leases is worth ≈ $0.67M over 24 months. Faster deal screening is upside that isn't counted here.

---

## 6. Why Databricks

Many products have an H3 function, a document parser or a chat-with-data feature. The difference here is **integration**: structured ERP data, unstructured documents, geospatial context, ML, natural-language analytics, an operational database and the business app all run on **one open, governed copy of the data**, with one security model and one lineage graph.

| Pillar | Proof in this build | Public customer evidence |
|---|---|---|
| Documents are governed data | Lineage runs lease PDF → parsed text → abstract → rent roll → Genie answer | First American: 100+ fields extracted from ~4M title-policy images; 70% lower cost, 75% less time |
| ML lives next to the data | Renewal model trained on document clauses + ERP history + H3 features, registered in Unity Catalog | Reonomy: 3× faster ML lifecycle; model to production in < 2 months |
| Geospatial is native SQL | `assets_near_deal`, `competitors_within`, `h3_coverash3` + `st_covers` neighborhood membership | Geospatial GenAI for real estate investment (H3 + spatial SQL + LLMs): 95% runtime reduction |
| NL analytics inherits governance | Genie answers respect the fund row filter; contact data is masked | JLL: built JLL Azara on Databricks SQL + Delta; 60% less ETL processing time |
| The app and its database are in the platform | Analyst correction → Lakebase → Delta → gold → Genie, no reverse-ETL tool | Demonstrated in this build |
| Third-party data by sharing, not copies | Documented plug-in for licensed property data (ATTOM, Cotality Marketplace listings) | ATTOM and Cotality publish on Databricks Marketplace |

---

## 7. How it works

```
ERP CDC files ─┐
Lease + deal PDFs ─┤ Lakeflow (Auto Loader, AUTO CDC, ai_parse_document, ai_extract, H3)
Overture Maps ─┘        │
                Unity Catalog: fund row filter, contact masks, tags, lineage, metric views, H3 functions
                        │
     ┌──────────────────┼────────────────────┬──────────────────────┐
  ML renewal model   Lakebase (Postgres)   Genie space          Databricks App
  (MLflow, UC)       synced + writeback    (11 benchmarks)      map · property 360 · review · Genie
```

---

## 8. Demo flow (20 minutes)

1. **Documents become data:** a lease PDF, its extracted terms, and the ERP mismatch it exposed. Lineage shows the path.
2. **Ask Genie:** rollover, co-tenancy and competitor density in one question; "show the SQL"; answers respect the fund row filter.
3. **Act on it:** in the app, an analyst corrects a flagged lease; the fix flows through Lakebase into gold and Genie.
4. **Screen a deal:** GP-ACQ-014. Nearby held assets, their occupancy, and the in-place lease terms from its offering memorandum.
5. **Price the risk:** expected vacancy loss by fund and the ten leases that drive it.

---

## 9. Decisions and trade-offs

| Choice | Why | Trade-off |
|---|---|---|
| Extract lease terms **inside the pipeline** (`ai_parse_document` + `ai_extract`) | Lineage, governance and incremental processing for documents, the same as for tables | Less control than custom prompts; mitigated by measuring every field |
| **Risk-weighted abstraction** (116 of 391 leases) | Spend follows risk: every lease expiring in 24 months, plus the 25 largest | Clause answers report coverage; full-portfolio abstraction comes in the pilot |
| **H3 + trusted functions** for spatial questions in Genie | Cheap spatial joins at 4M POIs; Genie calls tested logic instead of improvising it | "About 1 km" is approximate; exact polygons are used only for neighborhoods |
| **Security in Unity Catalog**, not the app | One fund filter for Genie, SQL and the app | Synced Lakebase tables need an unfiltered source, so the app guards Lakebase reads |
| **Lakebase** for the app, with corrections merged back to Delta | Millisecond reads and transactional writes | The app is as fresh as the last sync; corrections land on the next pipeline run |

Full list: `docs/DECISIONS.md`. How AI agents helped build it: `docs/BUILT_WITH_AI.md`.

---

## 10. Next steps

1. **Pilot (4–6 weeks):** 50–100 real leases and one deal data room, the existing ERP gold tables, and the Genie space for one fund team.
2. **Success criteria:** ≥ 95% accuracy on core terms on a reviewed sample; benchmark questions answered correctly; abstraction time per lease cut by ≥ 80%.
3. **Then:** licensed property data via Delta Sharing, the review queue in production, and Genie in the tools the deal team already uses.
