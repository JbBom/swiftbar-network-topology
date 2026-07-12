#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/aeg-report-export.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export AEG_STATE_DIR="$TEST_DIR/state"
export AEG_REPORT_DIR="$TEST_DIR/reports"
export AEG_HISTORY_FILE="$AEG_STATE_DIR/history.jsonl"
export AEG_LAST_STATE_FILE="$AEG_STATE_DIR/last-state"
export AEG_PROFILES_FILE="$ROOT_DIR/config/ai-apps.tsv"
export AEG_PROCESS_SOURCE_FILE="$TEST_DIR/processes.txt"
export NBM_SNAPSHOT_FILE="$TEST_DIR/baseline.json"
export AEG_NETWORK_JSON='{"status":"stable","changes":[]}'

mkdir -p "$AEG_STATE_DIR"
cat > "$NBM_SNAPSHOT_FILE" <<'JSON'
{"public_ipv4":"203.0.113.10","country":"US","asn":"AS64500","dns_resolver":["1.1.1.1"],"ipv6_available":false,"trusted_at":"2026-07-12T00:00:00Z"}
JSON
: > "$AEG_PROCESS_SOURCE_FILE"

export_output="$($ROOT_DIR/scripts/aeg-report-export.sh --tail 3)"
export_rc=$?
if [ "$export_rc" -ne 0 ]; then
  echo "report export failed: rc=$export_rc output=$export_output" >&2
  exit 1
fi

report_file="$(printf '%s\n' "$export_output" | sed -n 's/^Path: //p')"
if [ ! -f "$report_file" ]; then
  echo "exported report was not created: $report_file" >&2
  exit 1
fi
if ! grep -q 'AI Environment Guard 诊断报告' "$report_file"; then
  echo "exported report content is missing the title" >&2
  exit 1
fi

echo "aeg report export checks passed"
