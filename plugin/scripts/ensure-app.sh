#!/bin/bash
# Runs at Claude Code session start: builds Pip the first time, then makes sure it's running.
APP="${PIP_APP:-$HOME/Applications/Pip.app}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$APP" ]; then
  # First run: build in the background so the session isn't held up (~30s).
  nohup "$HERE/install-app.sh" >"${TMPDIR:-/tmp}/pip-install.log" 2>&1 &
  exit 0
fi

pgrep -x Pip >/dev/null 2>&1 || open -g "$APP" >/dev/null 2>&1
exit 0
