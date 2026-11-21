#!/bin/bash
# Tells the Pip app what your coding agent is doing.
# Usage: pip-event.sh <working|needs-input|done|hide|auto> [source]
#   "auto" reads a Claude Code Notification payload from stdin and picks the state.
# Always exits 0 quickly so it can never slow down or block your agent.

STATE="${1:-done}"
SOURCE="${2:-claude}"
PORT="${PIP_PORT:-47823}"
APP="${PIP_APP:-$HOME/Applications/Pip.app}"

INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null)"

json() { printf '%s' "$INPUT" | /usr/bin/jq -r "$1 // empty" 2>/dev/null; }

MSG=""
if [ "$STATE" = "auto" ]; then
  case "$(json .notification_type)" in
    permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input)
      STATE="needs-input"; MSG="$(json .message)" ;;
    *) exit 0 ;;   # idle reminders, auth messages, etc. stay quiet
  esac
fi

# Cursor's stop hook reports aborted/error runs; don't celebrate those.
if [ "$SOURCE" = "cursor" ] && [ "$STATE" = "done" ]; then
  case "$(json .status)" in
    aborted) STATE="hide" ;;
    error) MSG="Something went wrong. Take a look?" ;;
  esac
fi

send() {
  /usr/bin/curl -sfG -m 1 "http://127.0.0.1:$PORT/event" \
    --data-urlencode "state=$STATE" \
    --data-urlencode "source=$SOURCE" \
    --data-urlencode "message=$MSG" >/dev/null 2>&1
}

if ! send && [ -d "$APP" ] && [ "$STATE" != "hide" ]; then
  open -g "$APP" >/dev/null 2>&1
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
