#!/bin/bash
# Adds Pip to Cursor's global agent hooks (~/.cursor/hooks.json).
# Safe to run more than once; keeps any hooks you already have.
# Remove with: setup-cursor.sh --uninstall
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.cursor/hooks"
HOOKS_FILE="$HOME/.cursor/hooks.json"
SCRIPT="$HOOKS_DIR/pip-event.sh"

command -v jq >/dev/null || { echo "This script needs jq." >&2; exit 1; }
mkdir -p "$HOOKS_DIR"
[ -f "$HOOKS_FILE" ] || echo '{"version":1,"hooks":{}}' > "$HOOKS_FILE"
cp "$HOOKS_FILE" "$HOOKS_FILE.bak"

# Drop any existing Pip entries first.
STRIPPED="$(jq --arg s "$SCRIPT" '
  .version //= 1 | .hooks //= {}
  | .hooks |= with_entries(.value |= map(select((.command // "") | contains($s) | not)))
  | .hooks |= with_entries(select(.value | length > 0))
' "$HOOKS_FILE")"

if [ "${1:-}" = "--uninstall" ]; then
  printf '%s\n' "$STRIPPED" > "$HOOKS_FILE"
  rm -f "$SCRIPT"
  echo "Removed Pip from Cursor hooks."
  exit 0
fi

cp "$HERE/../plugin/scripts/pip-event.sh" "$SCRIPT"
chmod +x "$SCRIPT"

printf '%s\n' "$STRIPPED" | jq --arg s "$SCRIPT" '
  .hooks.beforeSubmitPrompt += [{"command": ("\"" + $s + "\" working cursor")}]
  | .hooks.stop += [{"command": ("\"" + $s + "\" done cursor")}]
' > "$HOOKS_FILE"

echo "Pip added to Cursor hooks ($HOOKS_FILE). Backup saved as hooks.json.bak."
echo "Restart Cursor if it's open."
