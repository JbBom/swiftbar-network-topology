#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/aeg-report.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export AEG_STATE_DIR="$TEST_DIR/state"
export AEG_HISTORY_FILE="$AEG_STATE_DIR/history.jsonl"
export AEG_LAST_STATE_FILE="$AEG_STATE_DIR/last-state"
export AEG_PROFILES_FILE="$ROOT_DIR/config/ai-apps.tsv"
export AEG_PROCESS_SOURCE_FILE="$TEST_DIR/processes.txt"
export NBM_SNAPSHOT_FILE="$TEST_DIR/baseline.json"

assert_contains() {
  local value="$1" expected="$2" message="$3"
  if ! printf '%s' "$value" | grep -q "$expected"; then
    echo "$message: $value" >&2
    exit 1
  fi
}

cat > "$NBM_SNAPSHOT_FILE" <<'JSON'
{"public_ipv4":"203.0.113.10","country":"US","asn":"AS64500","dns_resolver":["1.1.1.1"],"ipv6_available":false,"trusted_at":"2026-07-11T00:00:00Z"}
JSON

mkdir -p "$AEG_STATE_DIR"
cat > "$AEG_HISTORY_FILE" <<'JSONL'
{"checked_at":"2026-07-11T00:01:00Z","status":"caution","network":{"status":"drift"},"running_apps":[],"reasons":[{"code":"network_drift_before_launch","message":"当前网络与可信基线不一致。"}]}
JSONL

: > "$AEG_PROCESS_SOURCE_FILE"
stable_network='{"status":"stable","changes":[]}'
report_output="$($ROOT_DIR/scripts/aeg-report.sh --tail 5 --network-json "$stable_network")"
report_rc=$?
if [ "$report_rc" -ne 0 ]; then
  echo "report should return ready, got rc=$report_rc" >&2
  exit 1
fi

assert_contains "$report_output" 'AI Environment Guard 诊断报告' "report title missing"
assert_contains "$report_output" 'ASN：AS64500' "baseline ASN missing"
assert_contains "$report_output" '2026-07-11T00:01:00Z | caution' "history event missing or nested status used"
assert_contains "$report_output" '🟢 AI 环境：可以运行' "current assessment missing"

echo "aeg report checks passed"
