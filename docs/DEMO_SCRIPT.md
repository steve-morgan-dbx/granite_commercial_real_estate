# Demo voice track: Granite Peak Portfolio Intelligence

A 20-minute tell-show-tell for two people: the **Head of Transactions** (executive sponsor, cares about decisions and dollars) and the **Head of Asset Management / BI lead** (domain owner, cares about trust, self-service and workload). A technical evaluator may join; their objections are covered at the end.

Every number below comes from the committed build (`evidence/`). Granite Peak is fictional and the data is synthetic.

**Rules for delivery:** say the outcome before the click, name one number per beat, and stop talking while a query runs. If a live step fails, open the matching `evidence/` file and keep going.

---

## Before the call (10 minutes)

| Check | How |
|---|---|
| SQL warehouse warm | Run any query in the SQL editor |
| Lakebase instance `granite-cre` and the app are running | Compute → Apps; refresh the app once |
| Genie answers cached | Ask the three demo questions once in the Genie space |
| Review queue reset | In Lakebase: `DELETE FROM app.abstract_review WHERE lease_id = 'GP-LSE-00009';` |
| Tabs open, in order | 1 Deck · 2 Volume `landing/docs/leases` with `GP-LSE-00009.pdf` · 3 Catalog Explorer `lease_abstract` → Lineage · 4 Genie space · 5 App (Portfolio map, Albuquerque) · 6 `renewal_scores` in the SQL editor |
| Fallback | `evidence/` open in the GitHub repo |

---

## TELL: the outcome (3 minutes, deck slides 1–4)

**Say:**
> "Granite Peak owns 118 office, retail and industrial assets across eight Western metros: $370.8 million of annual base rent across 391 leases. In the next 24 months, $89.8 million of that rent comes up for renewal. That's 24% of the rent roll.
>
> Today nobody can tell you which of those leases are actually at risk. The clauses that decide it, like renewal options, co-tenancy and termination rights, are in PDFs. The rent roll is in the ERP, and nobody checks the two against each other. And nobody has mapped the competing supply around each building.
>
> What we built puts a price on that risk: **$34.5 million of expected vacancy loss over the next 24 months**, lease by lease. It also found **16 leases where the ERP and the signed lease disagree**, covering **$22.4 million of ABR**. And it lets your team ask those questions in plain English, against governed data."

**Land:** "That's roughly $1.4 million a year of value at the conservative end. I'll show you where each piece comes from."

*(Point to the value slide. Don't explain the math unless asked; see "Value objections" below.)*

**Transition:** "Let me show you the whole journey, starting with a single lease."

---

## SHOW (14 minutes)

### Beat 1: documents become data (3 min)

**Do:** Volume `landing/docs/leases/` → open `GP-LSE-00009.pdf` (Stone Legal Group, Salt Lake City).

**Say:**
> "This is a signed lease, a plain PDF in a governed Unity Catalog volume. The pipeline reads it with `ai_parse_document`, then `ai_extract` pulls out eleven terms: dates, rent, escalation type, renewal options, co-tenancy, termination rights, exclusive use."

**Do:** Catalog Explorer → `lease_abstract` → Sample data, filter `GP-LSE-00009`; then the **Lineage** tab.

**Say:**
> "Here's the abstract. The ERP says this lease ends in January 2028. The signed lease says October 2027. That's a three-month difference in when this tenant can walk. The pipeline compares every abstract to the ERP on every run, and it flagged 16 leases like this one.
>
> And this is the lineage: PDF, parsed text, abstract, rent roll, then the Genie space and the app. The documents follow the same governance and audit trail as your ERP tables."

**Land:** "On 116 test leases, every one of the eleven fields matched the source document. We measure accuracy against an answer key; we don't eyeball it."

*(If asked about real scanned leases, see "Accuracy on real leases" below.)*

### Beat 2: ask Genie (5 min)

**Do:** Genie space. Ask:
> *Which retail assets have more than 25% of ABR expiring within 24 months and a co-tenancy clause?*

**Say while it runs:**
> "This question needs three things that usually live in three systems: rollover from the ERP, co-tenancy from the PDFs, and property type from the asset master."

**Do:** Show the answer (5 retail assets, led by Granite Phoenix Retail 41 at 55.1%). Click **Show SQL**.

**Say:**
> "Five assets. Notice that Genie also reports *abstraction coverage*. Clause data only exists for leases we've abstracted, so Genie won't count a missing abstract as 'no co-tenancy'. We wrote that rule into the space. And here's the SQL, so your BI team can check every answer."

**Do:** Follow-up in the same conversation:
> *For deal GP-ACQ-014, which held assets are within about 2 km, and what's their occupancy?*

**Say:**
> "Now the transactions view. GP-ACQ-014 is a $56 million retail center in Portland, currently in due diligence. Genie calls a trusted H3 function we registered in Unity Catalog, so the spatial math is ours, not improvised. We own six assets within 2 km. Most are full, and one retail center is at 73%. That's the comp context, in seconds instead of days."

**Do (optional, if time allows):**
> *Which tenants with termination rights in the next 18 months have renewal probability below 40%?*
> "Ten tenants. That answer mixes a lease clause, a date, and a machine learning score in one question."

**Land:** "Each fund team can only see its own funds' rows. That's a row filter in Unity Catalog, so it applies the same way in Genie, SQL and the app."

*(Show the filter on `rent_roll` → Details if the domain owner asks how.)*

### Beat 3: act on it in the app (4 min)

**Do:** App → **Portfolio map** (opens on Albuquerque).

**Say:**
> "This is the asset manager's front door: a Databricks App, so there's no separate hosting. Each hex is the property's H3 cell. Color shows how much rent expires in the next 24 months, and height shows rent. Switch to competitor density and you can see which assets are surrounded by competing supply."

**Do:** **Property 360** → pick an asset. Point at the lookup time.

**Say:**
> "Property pages are served from Lakebase, Databricks' managed Postgres, in about 3 milliseconds. The pipeline keeps it in sync with the gold tables."

**Do:** **Lease review** → select `GP-LSE-00009` → the field defaults to `lease_end` and shows the PDF value (`2027-10-15`) next to the ERP value (`2028-01-13`) → load the PDF → approve the pre-filled ERP date.

**Say:**
> "This is the review queue: only the 16 flagged leases, not all 391. The analyst opens the PDF and decides which date is right. Say there's an extension that never made it into the lease file. Then they approve the ERP date, and the abstract is corrected. If the signed lease is right instead, the fix goes to the ERP team.
>
> The correction goes into Lakebase, and on the next pipeline run it reaches the gold tables. The flag clears, and Genie sees the corrected date. There's no export, no reverse-ETL tool, and it's the same security model."

**Land:** "Analysts review the exceptions instead of re-keying every lease. That's 350 to 700 analyst hours back per abstraction cycle."

### Beat 4: price the risk (2 min)

**Do:** SQL editor, `renewal_scores` ordered by `expected_vacancy_loss DESC`.

**Say:**
> "The renewal model is a gradient-boosted model trained on lease clauses from the documents, ERP payment history, and H3 neighborhood features. It's registered in Unity Catalog with MLflow. The top risk is Mesa Manufacturing in Phoenix: $5.6 million of rent, a 4% renewal probability, expiring January 2027. That's $4.1 million of expected vacancy loss from one lease.
>
> Across the portfolio, that's $34.5 million over 24 months. Every point of renewal rate you win back on the expiring leases is worth about $670,000."

**Land:** "This is the list your leasing team should be working this quarter."

---

## TELL: why it matters (3 minutes, deck slides 5–8)

**Say:**
> "Here's what you just saw: one lease PDF went through Lakeflow, Unity Catalog, an extraction model, Lakebase, Genie and an app. That's one copy of the data, one security model and one lineage graph, with no data copied between tools. Many products have a document parser or a chat-with-data feature. What's hard to get elsewhere is all of them on the same governed data."

**Customer proof (pick the one that fits the room):**
- Documents at scale → **First American**: 100+ fields extracted from about 4 million title-policy images; 70% lower cost, 75% less project time.
- Real estate analytics platform → **JLL Azara**, built on Databricks SQL and Delta; 60% less ETL processing time.
- ML in production → **Reonomy**: 3× faster ML lifecycle, from model to production in under two months.

**The ask:**
> "Our proposal is a 4–6 week pilot: 50 to 100 of your real leases, one deal data room, and one fund team using Genie. Success means at least 95% accuracy on core terms on a reviewed sample, the benchmark questions answered correctly, and abstraction time per lease cut by 80%. Who should we schedule the leases and data-room access with?"

---

## Objection bank

### Business stakeholder (Head of Transactions / Asset Management)

| Objection | Answer |
|---|---|
| **"Is 100% accuracy real?"** | "It's real on these documents, which are clean, machine-generated PDFs. Scanned leases with handwritten amendments will score lower. That's exactly what the pilot measures, field by field against a reviewed sample. The review queue exists for the cases the model gets wrong." |
| **"Where does the $34.5M come from?"** | "For each lease expiring in 24 months: (1 − renewal probability) × annual rent × 9 months of downtime to re-lease. Nine months is our assumption; plug in your own and the number moves with it." |
| **"Why should I trust the renewal model?"** | "On held-out data it ranks leases correctly 71% of the time (AUC 0.71). The training history here is synthetic. In the pilot we'd train it on your actual renewal outcomes, and you'd see which features drive it." |
| **"Our analysts already abstract leases."** | "Keep them. This flips their work from re-typing 391 leases to reviewing about 16 flagged ones, and it checks every lease against the ERP every time the pipeline runs, not once during an audit." |
| **"We use Yardi and a BI tool already."** | "We don't replace either one. Yardi stays the system of record, landed through change-data-capture files. Genie and the app sit next to your BI. What's new is that the lease clauses and market context land in the same governed tables." |
| **"Can a fund team see another fund's assets?"** | "No. The row filter is enforced in Unity Catalog, so Genie, SQL and the app all apply it. Tenant contact details are masked for everyone outside the PII group." |
| **"What does this cost?"** | "Serverless throughout, so you pay for pipeline runs, extraction calls, the warehouse, and a small Postgres instance. There's no idle cluster. The pilot gives us a measured cost per lease to set against the $150–400 per lease that outsourced abstraction typically costs." |
| **"Could Genie give a wrong answer to the IC?"** | "That's why we score it like code: 11 benchmark questions with known-good SQL, 10 correct and 1 partially correct, all published. Every answer shows its SQL, and the hard logic, like spatial proximity and WALT, lives in trusted functions and metric views, not in Genie's guesswork." |

### Technical stakeholder (data / platform architect)

| Objection | Answer |
|---|---|
| **"Why extract inside the pipeline instead of a separate service?"** | "Lineage, incremental processing and governance. Auto Loader only processes new PDFs, the extraction is a SQL step that gets the same retries and monitoring as any other, and the results inherit tags and masks." |
| **"How do you handle ERP changes?"** | "AUTO CDC builds SCD Type 1 dimensions and an SCD Type 2 lease history from Qlik-style change files. In production you'd use Lakeflow Connect or your existing replication tool and land the same format." |
| **"Why H3 instead of exact distances?"** | "H3 turns spatial joins into equality joins on a cell ID, which makes 4 million POIs cheap to work with. The k-ring is an approximation, which is fine for 'about 1 km'. For exact polygon membership, like which neighborhood an asset is in, we use H3 candidates and then `st_covers`." |
| **"Why Lakebase instead of querying the warehouse from the app?"** | "Millisecond lookups and transactional writes for the review queue. The warehouse is the right tool for analytics, not for row-level updates. The synced tables are snapshots refreshed by the pipeline; the trade-off is that the app is as fresh as the last sync." |
| **"Genie hallucinating spatial SQL?"** | "It doesn't write spatial SQL. It calls `assets_near_deal`, `assets_near` and `competitors_within`, which are Unity Catalog functions we wrote and tested. Join specs and column notes stop it from joining on the H3 cell." |
| **"Does the row filter apply in Lakebase?"** | "Not by itself: synced tables need an unfiltered source, so in this build the app is the access boundary for Lakebase reads, while Genie runs as the signed-in user and gets the UC filter. In production you'd add Postgres roles per group, or keep fund-sensitive reads on the Genie and SQL path." |
| **"How is this deployed and promoted?"** | "One Declarative Automation Bundle: the pipeline, jobs, app and variables are defined in the repo, and `bundle deploy -t <env>` promotes it. The build job runs end to end, and the evidence in the repo is that job's output." |
| **"What about model drift and monitoring?"** | "The model is versioned in the Unity Catalog registry and scored in batch into a governed table. Next steps are a Lakehouse Monitoring profile on `renewal_scores` and retraining on actual renewal outcomes." |

### Value objections

| Objection | Answer |
|---|---|
| **"$1.4M a year sounds made up."** | "It's the sum of three assumptions you can change: 3 points of renewal rate won back on the $89.8M expiring (about $1.0M a year), half of the $0.68M a year in rent differences across 12 mismatched leases resolved in your favor ($0.34M), and outsourced abstraction avoided ($0.06–0.16M). The renewal point is the big lever, and each point is worth about $670,000." |

---

## The 60-second version (if the room only has a minute)

> "Granite Peak has $370 million of rent across 391 leases, and 24% of it rolls in the next two years. The clauses that decide whether those tenants stay are buried in PDFs. We extract them in the data pipeline, check every lease against the ERP, and found 16 that disagree. Then we score every lease for renewal risk: $34.5 million of expected vacancy loss, lease by lease. Your team can ask 'which retail assets have big rollover and a co-tenancy clause?' in plain English and get a governed, auditable answer. And an analyst can fix a bad abstract in an app that writes straight back to the same data. It's one platform, one copy of the data, one security model."
