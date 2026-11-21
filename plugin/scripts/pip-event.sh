#!/bin/bash
# Tells the Pip app what your coding agent is doing.
# Usage: pip-event.sh <working|needs-input|done|sleep|auto> [source]
#   "auto" reads a Claude Code Notification payload from stdin and picks the state.
# Always exits 0 quickly so it can never slow down or block your agent.
# Works on a stock Mac: uses jq when present (macOS 15+), otherwise JavaScript for Automation.

STATE="${1:-done}"
SOURCE="${2:-claude}"
PORT="${PIP_PORT:-47823}"
APP="${PIP_APP:-$HOME/Applications/Pip.app}"
JQ="${PIP_JQ:-/usr/bin/jq}"

INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null)"

# Reads one top-level string field from the JSON payload.
field() {
  [ -n "$INPUT" ] || return 0
  if [ -x "$JQ" ]; then
    printf '%s' "$INPUT" | "$JQ" -r --arg k "$1" '.[$k] // empty | tostring' 2>/dev/null
  else
    /usr/bin/osascript -l JavaScript -e '
      function run(a) {
        try { var v = JSON.parse(a[0])[a[1]]; return v == null ? "" : String(v) } catch (e) { return "" }
      }' "$INPUT" "$1" 2>/dev/null
  fi
}

MSG=""
if [ "$STATE" = "auto" ]; then
  case "$(field notification_type)" in
    permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input)
      STATE="needs-input"; MSG="$(field message)" ;;
    *) exit 0 ;;   # idle reminders, auth messages, etc. stay quiet
  esac
fi

# Cursor's stop hook reports aborted/error runs; don't celebrate those.
if [ "$SOURCE" = "cursor" ] && [ "$STATE" = "done" ]; then
  case "$(field status)" in
    aborted) STATE="sleep" ;;
    error) MSG="Something went wrong. Take a look?" ;;
  esac
fi

send() {
  /usr/bin/curl -sfG -m 1 "http://127.0.0.1:$PORT/event" \
    --data-urlencode "state=$STATE" \
    --data-urlencode "source=$SOURCE" \
    --data-urlencode "message=$MSG" >/dev/null 2>&1
}

if ! send && [ -x "$APP/Contents/MacOS/Pip" ] && [ "$STATE" != "sleep" ]; then
  if [ -n "${PIP_PORT:-}" ]; then
    open -g --env "PIP_PORT=$PIP_PORT" "$APP" >/dev/null 2>&1
  else
    open -g "$APP" >/dev/null 2>&1
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.2
    send && break
  done
fi

# Cursor's beforeSubmitPrompt hook expects a JSON answer.
if [ "$SOURCE" = "cursor" ] && [ "$STATE" = "working" ]; then
  echo '{"continue": true}'
fi
exit 0
