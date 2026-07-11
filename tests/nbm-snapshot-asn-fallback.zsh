#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/nbm-snapshot.sh"

_nbm_fetch_url() {
  case "$1" in
    https://ipinfo.io/json)
      echo '{"status":429,"error":{"title":"Rate limit hit"}}'
      ;;
    https://api.myip.com)
      echo '{"ip":"203.0.113.10","cc":"US"}'
      ;;
    https://ipwho.is/203.0.113.10)
      echo '{"ip":"203.0.113.10","connection":{"asn":64500,"org":"Example Network"}}'
      ;;
  esac
}

snapshot="$(nbm_snapshot_collect)"
if ! printf '%s' "$snapshot" | grep -q '"asn": "AS64500"'; then
  echo "ASN fallback was not used: $snapshot" >&2
  exit 1
fi
if ! printf '%s' "$snapshot" | grep -q '"isp": "AS64500 Example Network"'; then
  echo "Fallback organization was not recorded: $snapshot" >&2
  exit 1
fi

echo "nbm snapshot ASN fallback checks passed"
