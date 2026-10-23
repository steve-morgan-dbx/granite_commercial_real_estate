# Built with AI: tools, prompts and patterns

This build was made by one person working with two AI coding agents, and it uses AI inside the product as well. This page records what each tool did, the prompts that shaped the work, and the patterns that kept the AI's output trustworthy.

## The team

| Teammate | Role in this build | Where it shows in the repo |
|---|---|---|
| **Human (solution architect)** | Picked the industry problem, personas, scope and fictional company. Approved every push. Made the judgment calls: what to cut, which numbers to stand behind, how to frame the value. | Commit history; decisions in [`DECISIONS.md`](DECISIONS.md) |
| **Genie Code** (Databricks' coding agent, in a workspace Git folder) | First pass in the workspace: the publishing rule, scaffold and structure tests, synthetic-data generator, Overture ingest notebook, and the first Lakeflow pipeline SQL. | The early commits authored from the workspace |
| **Claude Code** (CLI agent, using the Databricks CLI, SDK and REST APIs against the workspace) | Plan and design review. Debugged the first pass and finished the build: governance, metric views, the renewal model, Lakebase, the Genie space and benchmarks, the app, and the bundle. Deployed it, ran it, collected the evidence, and drafted the deck and this documentation. | `docs/PLAN.md` §9 (defects fixed), `scripts/`, `evidence/` |
| **AI inside the product** | `ai_parse_document` and `ai_extract` abstract lease and deal PDFs in the pipeline. Genie answers questions in natural language. | `pipelines/transformations/silver/documents.sql`, `src/genie/` |

The two agents worked one at a time, never together: pull, edit, push. Both followed the same rules file ([`CLAUDE.md`](../CLAUDE.md)).

## Prompts that shaped the build

These are lightly edited versions of the actual instructions, with customer details removed.

1. **Plan before building.**
   > "Create a plan for an end-to-end demo on a commercial real estate scenario: Lakeflow → Unity Catalog → Lakebase → ML/GenAI → Genie → Databricks App. Include free Marketplace data such as ATTOM or Cotality, and show how H3 can be used in Genie together with document parsing. Don't start building; refine the plan first."
2. **Ground the 'why' in evidence.**
   > "Make sure the customer stories answer 'Why can you only do this on Databricks?' Use only public references."
3. **Set guardrails before writing code.**
   > "This repo is public. Nothing proprietary or customer-identifying is ever published. Add the rule for every AI assistant that edits the repo, and enforce it with a check."
4. **Hand off between agents through the repo, not chat history.**
   > "I started working in a workspace Git folder with Genie Code. Pick up the plan where it left off, using the latest push."
5. **Ship the whole journey, then fix what the user sees.**
   > "Continue executing the plan." Later: "The map shows nothing. There's no legend. Rates should be percentages. Why can't I click a row in the review table and approve a correction?"

## Patterns that worked

**1. Rules in a file, enforced by code.** `CLAUDE.md` states the publishing rule for every person and AI assistant. `scripts/scrub_check.sh` enforces it as a pre-push hook, and `tests/test_structure.py` checks it again. The agents don't have to remember the rule; the push fails if they break it.

**2. Ground truth by construction.** The synthetic-data generator writes an answer key next to every lease PDF. AI extraction is scored field by field against that key on every run (`evidence/genai_document_extraction.json`). This turned two silent failures into visible numbers:
- 0% accuracy exposed a PDF layout bug that left every page almost empty.
- 48% accuracy on escalation type exposed a schema description that listed the wrong vocabulary. Fixing it raised the field to 100%.

**3. Benchmarks as unit tests for Genie.** Eleven questions with known-good SQL live in `src/genie/benchmarks.json`. `notebooks/07_genie_space.ipynb` rebuilds the space and re-scores it after every change. The fixes it drove: join specs to stop Genie joining on H3 cells, column notes, a coverage rule for clause questions, and rewording an ambiguous question. Result: 10 of 11 pass, 1 partial, and all are published.

**4. Evidence as code.** `scripts/export_run_notebooks.py` copies job-run outputs into the committed notebooks, and `scripts/collect_evidence.py` writes one JSON file per stage. Both scrub workspace hostnames and user paths. Evidence is regenerated, never hand-edited.

**5. The agent checks its own work against the platform, not against its own expectations.** After each stage the agent queried the result (row counts, accuracy, lineage, synced-table state, app status) before moving on. Defects it found this way and fixed, all listed in `docs/PLAN.md` §9:
- expired leases shown as occupied;
- the abstraction subset picking already-expired leases;
- clause fields leaking into the ERP extract;
- a NULL array path for deal tenant lists;
- an orphaned materialized view blocking a table name;
- synced Lakebase tables failing on re-create.

**6. The human owns judgment and outward actions.** The agent proposed and the human decided: the fictional company, which customer stories to use, the cut line, and every commit and push. The agent wrote down its caveats (synthetic labels, clean PDFs, workspace-local groups) rather than leaving them out.

## Where the AI got it wrong

Some mistakes, kept here because they show how they were caught:
- A size check the agent wrote to validate PDFs was itself wrong. It passed near-empty files. The ground-truth accuracy score caught it, not the check.
- The first `ai_extract` path for nested arrays returned NULL for every deal's tenant list. A row-count check on `deal_lease_terms` caught it.
- Unity Catalog grants to workspace-local groups failed. The agent replaced them with Genie-space permissions and documented the production fix rather than working around the platform.
- The first app release showed a blank map: no basemap, and hexes too small to see at the default zoom. A human using the app caught it, which is why the walkthrough is part of the plan.
