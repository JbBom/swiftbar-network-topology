#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/aeg-framework.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export AEG_STATE_DIR="$TEST_DIR/state"
export AEG_HISTORY_FILE="$AEG_STATE_DIR/history.jsonl"
export AEG_LAST_STATE_FILE="$AEG_STATE_DIR/last-state"
export AEG_HISTORY_MAX_ENTRIES=2
export AEG_PROFILES_FILE="$ROOT_DIR/config/ai-apps.tsv"
export AEG_PROCESS_SOURCE_FILE="$TEST_DIR/processes.txt"

assert_contains() {
  local value="$1"
  local expected="$2"
  local message="$3"
  if ! printf '%s' "$value" | grep -q "$expected"; then
    echo "$message: $value" >&2
    exit 1
  fi
}

assert_rc() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [ "$actual" -ne "$expected" ]; then
    echo "$message: expected rc=$expected, got rc=$actual" >&2
    exit 1
  fi
}

: > "$AEG_PROCESS_SOURCE_FILE"
stable_network='{"status":"stable","changes":[]}'

stable_output="$("$ROOT_DIR/scripts/aeg-assess.sh" --json --record --network-json "$stable_network")"
stable_rc=$?
assert_rc "$stable_rc" 0 "stable assessment failed"
assert_contains "$stable_output" '"status":"ready"' "stable assessment was not ready"

"$ROOT_DIR/scripts/aeg-assess.sh" --json --record --network-json "$stable_network" >/dev/null
history_lines="$(wc -l < "$AEG_HISTORY_FILE" | tr -d ' ')"
if [ "$history_lines" -ne 1 ]; then
  echo "unchanged stable state should produce one history line, got $history_lines" >&2
  exit 1
fi

cat > "$AEG_PROCESS_SOURCE_FILE" <<'PROCESSES'
100 /usr/local/bin/codex app-server
101 /usr/local/bin/node /Users/example/Documents/Claude Code/brave-search-curl.mjs
102 /Users/example/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/Service
PROCESSES

process_json="$("$ROOT_DIR/scripts/aeg-processes.sh" --json)"
assert_contains "$process_json" '"id":"codex-cli"' "Codex CLI was not detected"
if printf '%s' "$process_json" | grep -q '"id":"claude-code"'; then
  echo "directory name caused a false Claude Code detection: $process_json" >&2
  exit 1
fi
if printf '%s' "$process_json" | grep -q '102'; then
  echo "Codex helper directory caused a false CLI detection: $process_json" >&2
  exit 1
fi

drift_network='{"status":"drift","changes":[{"field":"public_ipv4","old":"203.0.113.10","new":"198.51.100.77"}]}'
alert_output="$("$ROOT_DIR/scripts/aeg-assess.sh" --json --record --network-json "$drift_network")"
alert_rc=$?
assert_rc "$alert_rc" 2 "running-app drift assessment failed"
assert_contains "$alert_output" '"status":"alert"' "running-app drift was not an alert"
assert_contains "$alert_output" '"id":"codex-cli"' "running app missing from alert"

"$ROOT_DIR/scripts/aeg-assess.sh" --json --record --network-json "$drift_network" >/dev/null
history_lines="$(wc -l < "$AEG_HISTORY_FILE" | tr -d ' ')"
if [ "$history_lines" -ne 2 ]; then
  echo "unchanged alert should not add history, got $history_lines lines" >&2
  exit 1
fi

: > "$AEG_PROCESS_SOURCE_FILE"
caution_output="$("$ROOT_DIR/scripts/aeg-assess.sh" --json --record --network-json "$drift_network")"
caution_rc=$?
assert_rc "$caution_rc" 1 "pre-launch drift assessment failed"
assert_contains "$caution_output" '"status":"caution"' "pre-launch drift was not caution"

history_lines="$(wc -l < "$AEG_HISTORY_FILE" | tr -d ' ')"
if [ "$history_lines" -ne 2 ]; then
  echo "history retention should keep two lines, got $history_lines" >&2
  exit 1
fi
if head -n 1 "$AEG_HISTORY_FILE" | grep -q '"status":"ready"'; then
  echo "history retention did not remove the oldest event" >&2
  exit 1
fi

unknown_network='{"status":"error","error":"no baseline found"}'
unknown_output="$("$ROOT_DIR/scripts/aeg-assess.sh" --json --network-json "$unknown_network")"
unknown_rc=$?
assert_rc "$unknown_rc" 1 "unknown environment assessment failed"
assert_contains "$unknown_output" '"status":"unknown"' "missing baseline was not unknown"

echo "aeg framework checks passed"
