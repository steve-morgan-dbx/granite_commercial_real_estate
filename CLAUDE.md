# Rules for working in this repository

These rules apply to every person and AI assistant that edits this repo.

## Publishing rule: nothing internal goes to the public repo

This repository is **public**. Only our own solution artifacts are published: code, notebooks with outputs, evidence, the plan and the deck, built on **synthetic or public open data** about the fictional company **Granite Peak Real Estate Partners**.

### Never commit or push

- Real customer names, abbreviations, account or opportunity IDs, or any content that identifies a customer
- Names of real people (customer staff or Databricks staff), or internal contacts and owners
- Real customer data, records or documents, even if partially scrubbed
- Revenue, ARR, consumption or deal figures for any company
- Internal-only material: account notes, session prep, internal customer stories, internal program or evaluation requirements, internal roadmaps
- Internal links: Google Docs/Drive/Slides, Slack, Jira/Confluence, `go/` links, internal GitHub orgs, internal workspace URLs
- Credentials, tokens, keys, `.databrickscfg`, `.env` files

### Allowed

- Synthetic data, and public open data with its license noted (for example Overture Maps)
- Public Databricks pages: customer stories, blogs, docs
- Public product names used generically (for example "shaped like Yardi Voyager")

### Where non-public material goes

1. Put it under `internal/`. That folder is ignored by `.gitignore`, so it stays local to the workspace.
2. If a non-public file has to live anywhere else, add its path (or a pattern for it) to `.gitignore` **in the same change, before it is staged**. You can also name it `*.internal.*`, which is already ignored.
3. Add any new customer-identifying term to the local, untracked `.scrub_terms` file (one regex per line) so the scrub check catches it.
4. Never reference the contents of `internal/` in tracked files. Restate the idea generically, using Granite Peak.

### Before every commit and push

- `git status` shows nothing from `internal/` or any other non-public path.
- `scripts/scrub_check.sh` passes. It also runs as a pre-push hook once `scripts/install_hooks.sh` has been run. It fails on credentials, internal links, customer terms from `.scrub_terms`, and tracked files that match `.gitignore`.
- Notebook outputs and `evidence/` files are checked too: no internal workspace hostnames, user emails or tokens in the output.

### If something internal was committed

- **Not pushed yet:** remove it from the commit (`git rm --cached <path>`, add it to `.gitignore`, then amend).
- **Already pushed:** stop and tell the repo owner. Rotate any exposed credential, rewrite history to remove the content, and force-push.
