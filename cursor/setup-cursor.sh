#!/bin/bash
# Adds Pip to Cursor's global agent hooks (~/.cursor/hooks.json).
# Safe to run more than once; keeps any hooks you already have.
# Remove with: setup-cursor.sh --uninstall
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.cursor/hooks"
HOOKS_FILE="$HOME/.cursor/hooks.json"
SCRIPT="$HOOKS_DIR/pip-event.sh"
MODE="${1:-install}"

mkdir -p "$HOOKS_DIR"
[ -f "$HOOKS_FILE" ] && cp "$HOOKS_FILE" "$HOOKS_FILE.bak"

if [ "$MODE" != "--uninstall" ]; then
  cp "$HERE/../plugin/scripts/pip-event.sh" "$SCRIPT"
  chmod +x "$SCRIPT"
fi

# Edit the JSON with Python (ships with Xcode Command Line Tools, which Pip needs anyway).
/usr/bin/python3 -I - "$HOOKS_FILE" "$SCRIPT" "$MODE" <<'PY'
import json, os, sys

path, script, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        config = json.load(f)
except FileNotFoundError:
    config = {}
except json.JSONDecodeError:
    sys.exit(f"{path} isn't valid JSON; fix it or move it aside, then run this again.")

config.setdefault("version", 1)
hooks = config.setdefault("hooks", {})

# Drop any existing Pip entries first, so this is safe to re-run.
for event in list(hooks):
    hooks[event] = [h for h in hooks[event] if script not in h.get("command", "")]
    if not hooks[event]:
        del hooks[event]

if mode != "--uninstall":
    quoted = '"' + script + '"'
    hooks.setdefault("beforeSubmitPrompt", []).append({"command": quoted + " working cursor"})
    hooks.setdefault("stop", []).append({"command": quoted + " done cursor"})

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY

if [ "$MODE" = "--uninstall" ]; then
  rm -f "$SCRIPT"
  echo "Removed Pip from Cursor hooks."
else
  echo "Pip added to Cursor hooks ($HOOKS_FILE)."
  [ -f "$HOOKS_FILE.bak" ] && echo "Your previous file is saved as hooks.json.bak."
  echo "Restart Cursor if it's open."
fi
