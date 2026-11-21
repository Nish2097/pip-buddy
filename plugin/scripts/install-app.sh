#!/bin/bash
# Builds Pip from source and installs it to ~/Applications/Pip.app.
# Building locally means macOS doesn't quarantine it, so no Apple signing is needed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SRC="$HERE/../app"
DEST="${PIP_APP:-$HOME/Applications/Pip.app}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Pip needs Swift. Install Xcode Command Line Tools with: xcode-select --install" >&2
  exit 1
fi

echo "Building Pip..."
cd "$APP_SRC"
swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path 2>/dev/null)/Pip"
[ -f "$BIN" ] || BIN="$(find .build -path '*release/Pip' -type f | head -1)"

# Quit a running copy so we can replace it.
pkill -x Pip 2>/dev/null || true

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
cp "$BIN" "$DEST/Contents/MacOS/Pip"
cat > "$DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pip</string>
  <key>CFBundleDisplayName</key><string>Pip</string>
  <key>CFBundleIdentifier</key><string>dev.pip.companion</string>
  <key>CFBundleExecutable</key><string>Pip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as a consistent app.
codesign --force --sign - "$DEST" >/dev/null 2>&1 || true

echo "Installed Pip to $DEST"
open -g "$DEST"
