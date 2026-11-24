#!/usr/bin/env bash
# Usage: run.sh — build Debug, sign with "Perroquet Dev" when present (else ad-hoc), relaunch Perroquet.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/Perroquet.xcodeproj"
CONFIG="Debug"
DERIVED_DATA="$ROOT/build"
APP="$DERIVED_DATA/Build/Products/$CONFIG/Perroquet.app"

if ! xcodebuild -version &>/dev/null; then
  if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo "error: Xcode is required (not just Command Line Tools)." >&2
    echo "Install Xcode from the App Store, then:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi
fi

IDENTITY="-"
if security find-identity -v -p codesigning | grep -q '"Perroquet Dev"'; then
  IDENTITY="Perroquet Dev"
else
  echo "warning: ad-hoc signing; run tools/make_signing_identity.sh once, otherwise Accessibility must be re-granted after every build." >&2
fi

echo "→ Building ($CONFIG, signed with \"$IDENTITY\")…"
xcodebuild \
  -project "$PROJECT" \
  -scheme Perroquet \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="" \
  2>&1 | { grep -v -E 'DVTCoreDeviceCore|CoreSimulator|CoreDevice|DVTPlugIn|^Details:|^\s+Expected in' || true; } | tail -n 5

if [[ ! -d "$APP" ]]; then
  echo "error: binary not found: $APP" >&2
  exit 1
fi

touch "$APP"
xattr -cr "$APP" 2>/dev/null || true
osascript -e 'tell application "Perroquet" to quit' 2>/dev/null || true
for _ in {1..50}; do
  pgrep -xq Perroquet || break
  sleep 0.1
done
if pgrep -xq Perroquet; then
  pkill -x Perroquet || true
  for _ in {1..30}; do
    pgrep -xq Perroquet || break
    sleep 0.1
  done
fi

echo "→ Launching $APP"
open "$APP" || { sleep 1; open "$APP"; }
