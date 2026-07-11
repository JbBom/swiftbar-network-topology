#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/aeg-preflight.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export AEG_STATE_DIR="$TEST_DIR/state"
export AEG_HISTORY_FILE="$AEG_STATE_DIR/history.jsonl"
export AEG_LAST_STATE_FILE="$AEG_STATE_DIR/last-state"
export AEG_PROFILES_FILE="$ROOT_DIR/config/ai-apps.tsv"
export AEG_PROCESS_SOURCE_FILE="$TEST_DIR/processes.txt"

assert_rc() {
  local actual="$1" expected="$2" message="$3"
  if [ "$actual" -ne "$expected" ]; then
    echo "$message: expected rc=$expected, got rc=$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local value="$1" expected="$2" message="$3"
  if ! printf '%s' "$value" | grep -q "$expected"; then
    echo "$message: $value" >&2
    exit 1
  fi
}

stable_network='{"status":"stable","changes":[]}'
drift_network='{"status":"drift","changes":[{"field":"public_ipv4","old":"203.0.113.10","new":"198.51.100.77"}]}'
error_network='{"status":"error","error":"no baseline found"}'

: > "$AEG_PROCESS_SOURCE_FILE"
ready_output="$($ROOT_DIR/scripts/aeg-preflight.sh --human --network-json "$stable_network")"
ready_rc=$?
assert_rc "$ready_rc" 0 "ready preflight failed"
assert_contains "$ready_output" '结论：可以启动 AI 工具' "ready preflight conclusion missing"

caution_output="$($ROOT_DIR/scripts/aeg-preflight.sh --human --network-json "$drift_network")"
caution_rc=$?
assert_rc "$caution_rc" 1 "caution preflight failed"
assert_contains "$caution_output" '结论：请先确认' "caution preflight conclusion missing"

cat > "$AEG_PROCESS_SOURCE_FILE" <<'PROCESSES'
100 /usr/local/bin/codex app-server
PROCESSES
alert_json="$($ROOT_DIR/scripts/aeg-preflight.sh --json --network-json "$drift_network")"
alert_rc=$?
assert_rc "$alert_rc" 2 "alert preflight failed"
assert_contains "$alert_json" '"status":"alert"' "alert JSON output missing"

: > "$AEG_PROCESS_SOURCE_FILE"
unknown_output="$($ROOT_DIR/scripts/aeg-preflight.sh --human --network-json "$error_network")"
unknown_rc=$?
assert_rc "$unknown_rc" 1 "unknown preflight failed"
assert_contains "$unknown_output" '结论：请先确认' "unknown preflight conclusion missing"

echo "aeg preflight checks passed"
