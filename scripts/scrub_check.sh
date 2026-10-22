#!/usr/bin/env bash
# Fails if tracked files contain customer-identifying terms or credentials.
# This repo is public: run before every push (installed as a pre-push hook by scripts/install_hooks.sh).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Customer terms are kept out of this file; supply them via a local, untracked file (one regex per line).
TERMS_FILE=".scrub_terms"
SECRET_PATTERN='dapi[0-9a-f]{32}|gh[pousr]_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
# Internal links and hosts (see CLAUDE.md, "Publishing rule").
INTERNAL_PATTERN='docs\.google\.com|drive\.google\.com|[a-z0-9-]+\.atlassian\.net|[a-z0-9-]+\.slack\.com|github\.com/databricks-field-eng|[a-z0-9-]+\.cloud\.databricks\.com|[a-z0-9-]+\.azuredatabricks\.net|(^|[^A-Za-z0-9])go/[a-z]|@databricks\.com'

status=0
if git grep -nIE "$SECRET_PATTERN" -- . ':!scripts/scrub_check.sh'; then
  echo "scrub_check: possible credential found" >&2; status=1
fi
if git grep -nIiE "$INTERNAL_PATTERN" -- . ':!scripts/scrub_check.sh'; then
  echo "scrub_check: internal link, host or email found" >&2; status=1
fi
# Tracked files that .gitignore says must stay local (e.g. internal/).
if [[ -n "$(git ls-files -ci --exclude-standard)" ]]; then
  git ls-files -ci --exclude-standard >&2
  echo "scrub_check: tracked file matches .gitignore (non-public path); git rm --cached it" >&2; status=1
fi
if [[ -f "$TERMS_FILE" ]]; then
  if git grep -nIiE -f "$TERMS_FILE" -- . ':!scripts/scrub_check.sh'; then
    echo "scrub_check: customer-identifying term found" >&2; status=1
  fi
else
  echo "scrub_check: warning: $TERMS_FILE not found, skipping customer-term check" >&2
fi
[[ $status -eq 0 ]] && echo "scrub_check: clean"
exit $status
