#!/bin/zsh
#
# Shared paths and JSON helpers for AI Environment Guard.

AEG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

: "${AEG_STATE_DIR:=$HOME/.nbm}"
: "${AEG_HISTORY_FILE:=$AEG_STATE_DIR/history.jsonl}"
: "${AEG_LAST_STATE_FILE:=$AEG_STATE_DIR/aeg-last-state}"
: "${AEG_LAST_ALERT_STATUS_FILE:=$AEG_STATE_DIR/aeg-last-alert-status}"
: "${AEG_HISTORY_MAX_ENTRIES:=500}"
: "${AEG_PROFILES_FILE:=$AEG_SCRIPT_DIR/../config/ai-apps.tsv}"

aeg_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

aeg_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

aeg_json_quote() {
  printf '"%s"' "$(aeg_json_escape "$1")"
}
