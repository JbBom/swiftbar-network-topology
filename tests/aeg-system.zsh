#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/aeg-system.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export AEG_STATE_DIR="$TEST_DIR/state"
export AEG_SYSTEM_BASELINE_FILE="$AEG_STATE_DIR/system-baseline.json"
export AEG_SYSTEM_OS_VERSION="26.5.1"
export AEG_SYSTEM_ARCHITECTURE="arm64"
export AEG_SYSTEM_TIMEZONE="Asia/Shanghai"
export AEG_SYSTEM_LOCALE="zh-Hans_US"
export AEG_SYSTEM_PRIMARY_INTERFACE="en0"
export AEG_SYSTEM_PROXY_ENABLED="true"

assert_rc() {
  local actual="$1" expected="$2" message="$3"
  if [ "$actual" -ne "$expected" ]; then
    echo "$message: expected rc=$expected, got rc=$actual" >&2
    exit 1
  fi
}

"$ROOT_DIR/scripts/aeg-system.sh" trust --yes >/dev/null

stable_output="$($ROOT_DIR/scripts/aeg-system.sh check --json)"
stable_rc=$?
assert_rc "$stable_rc" 0 "stable system check failed"
if [ "$stable_output" != '{"status":"stable","changes":[]}' ]; then
  echo "unexpected stable output: $stable_output" >&2
  exit 1
fi

export AEG_SYSTEM_TIMEZONE="America/Los_Angeles"
drift_output="$($ROOT_DIR/scripts/aeg-system.sh check --json)"
drift_rc=$?
assert_rc "$drift_rc" 1 "system drift check failed"
if ! printf '%s' "$drift_output" | grep -q '"field":"timezone"'; then
  echo "timezone drift was not reported: $drift_output" >&2
  exit 1
fi

rm -f "$AEG_SYSTEM_BASELINE_FILE"
missing_output="$($ROOT_DIR/scripts/aeg-system.sh check --json)"
missing_rc=$?
assert_rc "$missing_rc" 2 "missing system baseline check failed"
if [ "$missing_output" != '{"status":"error","error":"no system baseline found"}' ]; then
  echo "unexpected missing baseline output: $missing_output" >&2
  exit 1
fi

echo "aeg system checks passed"
