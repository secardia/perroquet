# Shared helpers for debug.sh, install.sh and tools/make_signing_identity.sh. Meant to be sourced, not run.
# build_app needs the caller to set ROOT to the repo root.

# Falls back to /Applications/Xcode.app when only the Command Line Tools are selected.
require_xcode() {
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
}

# Name of the local self-signed code-signing identity that signs both apps (Perroquet and Perroquet Dev).
SIGNING_IDENTITY="Perroquet"

# Prints the signing identity: $SIGNING_IDENTITY when it exists, else "-" (ad hoc).
pick_identity() {
  if security find-identity -v -p codesigning | grep -q "\"$SIGNING_IDENTITY\""; then
    echo "$SIGNING_IDENTITY"
  else
    echo "warning: ad-hoc signing; run tools/make_signing_identity.sh once, otherwise Accessibility must be re-granted after every build." >&2
    echo "-"
  fi
}

# Builds the Perroquet scheme into $ROOT/build and prints the app path:
# build_app <Debug|Release> <identity> <app name, e.g. "Perroquet Dev">.
build_app() {
  local config="$1" identity="$2" name="$3"
  local app="$ROOT/build/Build/Products/$config/$name.app"
  echo "→ Building ($config, signed with \"$identity\")…" >&2
  xcodebuild \
    -project "$ROOT/Perroquet.xcodeproj" \
    -scheme Perroquet \
    -configuration "$config" \
    -derivedDataPath "$ROOT/build" \
    build \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    CODE_SIGNING_REQUIRED=YES \
    DEVELOPMENT_TEAM="" \
    2>&1 | { grep -v -E 'DVTCoreDeviceCore|CoreSimulator|CoreDevice|DVTPlugIn|^Details:|^\s+Expected in' || true; } | tail -n 5 >&2 || exit 1
  if [[ ! -d "$app" ]]; then
    echo "error: binary not found: $app" >&2
    exit 1
  fi
  echo "$app"
}

# Quits a running app by exact process name: quit_app <process name>.
quit_app() {
  local name="$1"
  pgrep -xq "$name" || return 0
  osascript -e "tell application \"$name\" to quit" 2>/dev/null || true
  for _ in {1..50}; do
    pgrep -xq "$name" || break
    sleep 0.1
  done
  if pgrep -xq "$name"; then
    pkill -x "$name" || true
    for _ in {1..30}; do
      pgrep -xq "$name" || break
      sleep 0.1
    done
  fi
}
