#!/bin/bash
# Builds Pip from source and installs it to ~/Applications/Pip.app.
# Building locally means macOS doesn't quarantine it, so no Apple signing is needed.
#
# Options (environment variables):
#   PIP_APP      where to install (default ~/Applications/Pip.app)
#   PIP_NOTIFY=1 show a macOS notification if the build fails (used for background builds)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
APP_SRC="$PLUGIN_ROOT/app"
DEST="${PIP_APP:-$HOME/Applications/Pip.app}"
LOCK="${TMPDIR:-/tmp}/pip-install.lock"

fail() {
  echo "Pip: $1" >&2
  if [ "${PIP_NOTIFY:-}" = "1" ]; then
    /usr/bin/osascript -e "display notification \"$1\" with title \"Pip couldn't install\"" >/dev/null 2>&1
  fi
  exit 1
}

# One build at a time (e.g. two Claude Code sessions starting together).
# A lock older than 10 minutes is left over from a crash, so take it over.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    echo "Pip is already being installed."; exit 0
  fi
fi
trap 'rm -rf "$LOCK"' EXIT

if ! xcrun --find swift >/dev/null 2>&1; then
  fail "Install Xcode Command Line Tools first: xcode-select --install"
fi

VERSION="$(/usr/bin/sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
VERSION="${VERSION:-0.0.0}"

echo "Building Pip $VERSION..."
cd "$APP_SRC" || fail "Can't find the app source at $APP_SRC"
# Build for this Mac only: Pip is always built on the Mac that runs it.
xcrun swift build -c release 2>&1 | tail -20 || true
BIN="$(xcrun swift build -c release --show-bin-path 2>/dev/null)/Pip"
[ -x "$BIN" ] || fail "The build failed. Run $HERE/install-app.sh in Terminal to see why."

# Quit only the copy we're about to replace.
pkill -f "$DEST/Contents/MacOS/Pip" 2>/dev/null && sleep 0.3

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" || fail "Can't write to $DEST"
cp "$BIN" "$DEST/Contents/MacOS/Pip"
cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pip</string>
  <key>CFBundleDisplayName</key><string>Pip</string>
  <key>CFBundleIdentifier</key><string>dev.pip.companion</string>
  <key>CFBundleExecutable</key><string>Pip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as one consistent app.
codesign --force --sign - "$DEST" >/dev/null 2>&1 || true

echo "Installed Pip $VERSION to $DEST"
if [ -n "${PIP_PORT:-}" ]; then
  open -g --env "PIP_PORT=$PIP_PORT" "$DEST"
else
  open -g "$DEST"
fi
