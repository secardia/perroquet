#!/usr/bin/env bash
# Usage: debug.sh — build Debug, sign with "Perroquet Dev" when present (else ad-hoc),
# quit Perroquet and any running Perroquet Dev, then launch Perroquet Dev.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/tools/common.sh"

require_xcode
APP="$(build_app Debug "$(pick_identity)" "Perroquet Dev")"

touch "$APP"
xattr -cr "$APP" 2>/dev/null || true
quit_app "Perroquet"
quit_app "Perroquet Dev"

echo "→ Launching $APP"
open "$APP" || { sleep 1; open "$APP"; }
