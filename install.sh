#!/usr/bin/env bash
# Usage: [INSTALL_DIR=<dir>] install.sh — build Release, sign with "Perroquet" when present
# (else ad-hoc), zip it, and install Perroquet.app into INSTALL_DIR (default /Applications).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/tools/common.sh"

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DEST="$INSTALL_DIR/Perroquet.app"

require_xcode
APP="$(build_app Release "$(pick_identity)" "Perroquet")"
ZIP="$(dirname "$APP")/Perroquet.zip"

echo "→ Packaging Perroquet.zip…"
rm -f "$ZIP"
(
  cd "$(dirname "$APP")"
  ditto -c -k --sequesterRsrc --keepParent "Perroquet.app" "$ZIP"
)

quit_app "Perroquet"

echo "→ Installing to ${DEST}…"
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
touch "$DEST"

echo ""
echo "✓ Perroquet installed to $DEST"
echo "✓ $ZIP"
