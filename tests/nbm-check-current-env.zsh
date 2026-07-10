#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/nbm-current-env.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

export NBM_SNAPSHOT_FILE="$TEST_DIR/baseline.json"

cat > "$NBM_SNAPSHOT_FILE" <<'JSON'
{
  "public_ipv4": "203.0.113.10",
  "country": "US",
  "region": "California",
  "asn": "AS64500",
  "isp": "AS64500 Example Network",
  "dns_resolver": ["1.1.1.1","1.0.0.1"],
  "ipv6_available": false,
  "collected_at": "2026-07-10T00:00:00Z",
  "trusted_at": "2026-07-10T00:00:00Z",
  "source": "test"
}
JSON

run_shared_check() {
  NBM_CURRENT_STATE_READY=1 \
  NBM_CURRENT_PUBLIC_IPV4="${NBM_TEST_IP:-203.0.113.10}" \
  NBM_CURRENT_COUNTRY="US" \
  NBM_CURRENT_ASN="AS64500" \
  NBM_CURRENT_DNS_RESOLVER='["1.1.1.1","1.0.0.1"]' \
  NBM_CURRENT_IPV6_AVAILABLE="false" \
    "$ROOT_DIR/scripts/nbm-check.sh" --json --current-env
}

stable_output="$(run_shared_check)"
stable_rc=$?
if [ "$stable_rc" -ne 0 ] || [ "$stable_output" != '{"status":"stable","changes":[]}' ]; then
  echo "Expected stable shared-state result, got rc=$stable_rc: $stable_output" >&2
  exit 1
fi

NBM_TEST_IP="198.51.100.77"
export NBM_TEST_IP
drift_output="$(run_shared_check)"
drift_rc=$?
if [ "$drift_rc" -ne 1 ] ||
   ! echo "$drift_output" | grep -q '"status":"drift"' ||
   ! echo "$drift_output" | grep -q '"field":"public_ipv4"'; then
  echo "Expected public IPv4 drift, got rc=$drift_rc: $drift_output" >&2
  exit 1
fi

incomplete_output="$("$ROOT_DIR/scripts/nbm-check.sh" --json --current-env)"
incomplete_rc=$?
if [ "$incomplete_rc" -ne 2 ] ||
   [ "$incomplete_output" != '{"status":"error","error":"current state environment incomplete"}' ]; then
  echo "Expected incomplete-state error, got rc=$incomplete_rc: $incomplete_output" >&2
  exit 1
fi

echo "nbm current-env checks passed"
