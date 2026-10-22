#!/usr/bin/env bash
# Installs a pre-push hook that runs scripts/scrub_check.sh.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
printf '#!/usr/bin/env bash\nexec "%s/scripts/scrub_check.sh"\n' "$root" > "$root/.git/hooks/pre-push"
chmod +x "$root/.git/hooks/pre-push"
echo "pre-push hook installed"
