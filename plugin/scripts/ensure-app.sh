#!/bin/bash
# Runs when a Claude Code session starts. Builds Pip the first time (and again after
# a plugin update), otherwise just makes sure it's running. Always returns quickly.
APP="${PIP_APP:-$HOME/Applications/Pip.app}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WANT="$(/usr/bin/sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$HERE/../.claude-plugin/plugin.json" 2>/dev/null | head -1)"
HAVE="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null)"

if [ ! -x "$APP/Contents/MacOS/Pip" ] || [ "$WANT" != "$HAVE" ]; then
  # Build in the background (about 30 seconds) so the session isn't held up.
  PIP_NOTIFY=1 nohup "$HERE/install-app.sh" >"${TMPDIR:-/tmp}/pip-install.log" 2>&1 </dev/null &
  exit 0
fi

if ! pgrep -f "$APP/Contents/MacOS/Pip" >/dev/null 2>&1; then
  if [ -n "${PIP_PORT:-}" ]; then open -g --env "PIP_PORT=$PIP_PORT" "$APP"; else open -g "$APP"; fi
fi
exit 0
