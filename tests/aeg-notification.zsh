#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/aeg-notification.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export AEG_STATE_DIR="$TEST_DIR/state"
export AEG_HISTORY_FILE="$AEG_STATE_DIR/history.jsonl"
export AEG_LAST_STATE_FILE="$AEG_STATE_DIR/last-state"
export AEG_LAST_ALERT_STATUS_FILE="$AEG_STATE_DIR/last-alert-status"
export AEG_PROFILES_FILE="$ROOT_DIR/config/ai-apps.tsv"
export AEG_PROCESS_SOURCE_FILE="$TEST_DIR/processes.txt"
export AEG_NOTIFICATION_COMMAND="$TEST_DIR/notify.sh"
export AEG_NOTIFICATION_LOG="$TEST_DIR/notifications.log"

cat > "$AEG_NOTIFICATION_COMMAND" <<'NOTIFIER'
#!/bin/zsh
printf '%s\t%s\n' "$1" "$2" >> "$AEG_NOTIFICATION_LOG"
NOTIFIER
chmod +x "$AEG_NOTIFICATION_COMMAND"

assert_lines() {
  local expected="$1"
  local actual=0
  [ -f "$AEG_NOTIFICATION_LOG" ] && actual="$(wc -l < "$AEG_NOTIFICATION_LOG" | tr -d ' ')"
  if [ "$actual" -ne "$expected" ]; then
    echo "expected $expected notifications, got $actual" >&2
    exit 1
  fi
}

stable_network='{"status":"stable","changes":[]}'
drift_network='{"status":"drift","changes":[{"field":"public_ipv4","old":"203.0.113.10","new":"198.51.100.77"}]}'

: > "$AEG_PROCESS_SOURCE_FILE"
"$ROOT_DIR/scripts/aeg-assess.sh" --json --notify-on-alert --network-json "$stable_network" >/dev/null
assert_lines 0

cat > "$AEG_PROCESS_SOURCE_FILE" <<'PROCESSES'
100 /usr/local/bin/codex app-server
PROCESSES
"$ROOT_DIR/scripts/aeg-assess.sh" --json --notify-on-alert --network-json "$drift_network" >/dev/null || true
assert_lines 1

"$ROOT_DIR/scripts/aeg-assess.sh" --json --notify-on-alert --network-json "$drift_network" >/dev/null || true
assert_lines 1

"$ROOT_DIR/scripts/aeg-assess.sh" --json --notify-on-alert --network-json "$stable_network" >/dev/null
"$ROOT_DIR/scripts/aeg-assess.sh" --json --notify-on-alert --network-json "$drift_network" >/dev/null || true
assert_lines 2

echo "aeg notification checks passed"
