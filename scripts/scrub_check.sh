#!/usr/bin/env bash
# Fails if tracked files contain customer-identifying terms or credentials.
# This repo is public: run before every push (installed as a pre-push hook by scripts/install_hooks.sh).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Customer terms are kept out of this file; supply them via a local, untracked file (one regex per line).
TERMS_FILE=".scrub_terms"
SECRET_PATTERN='dapi[0-9a-f]{32}|gh[pousr]_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

status=0
if git grep -nIE "$SECRET_PATTERN" -- . ':!scripts/scrub_check.sh'; then
  echo "scrub_check: possible credential found" >&2; status=1
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
