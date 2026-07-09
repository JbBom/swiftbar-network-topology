#!/bin/zsh
#
# nbm-snapshot.sh — Network Baseline Monitor: snapshot data model
#
# Source-able script. Defines the snapshot data structure and functions
# to collect, save, and load a network baseline.
#
# Usage:
#   source scripts/nbm-snapshot.sh
#   nbm_snapshot_collect          # print current network state as JSON
#   nbm_snapshot_save             # save current state to baseline file
#   nbm_snapshot_load             # read baseline file, print JSON to stdout

: ${NBM_SNAPSHOT_FILE:="$HOME/.nbm/baseline.json"}

# ---- helpers ----------------------------------------------------------

_nbm_trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

_nbm_json_escape() {
  # minimal JSON string escaping
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

_nbm_fetch_url() {
  local url="$1"
  curl --connect-timeout 3 -L -m 5 -s "$url" 2>/dev/null
}

# ---- data collection ---------------------------------------------------

nbm_snapshot_collect() {
  local public_ipv4="" country="" region="" asn="" isp=""
  local dns_resolver_json="" ipv6_available="false"
  local now source

  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # --- public IP, country, ASN via ipinfo.io (has org/ASN field) -------
  local ipinfo
  ipinfo="$(_nbm_fetch_url "https://ipinfo.io/json")"

  if [ -n "$ipinfo" ]; then
    public_ipv4="$(echo "$ipinfo" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | _nbm_trim)"
    country="$(echo "$ipinfo" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | _nbm_trim)"
    region="$(echo "$ipinfo" | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | _nbm_trim)"
    isp="$(echo "$ipinfo" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | _nbm_trim)"

    # extract ASN from org field (format: "AS13335 Cloudflare, Inc.")
    if [ -n "$isp" ]; then
      asn="$(echo "$isp" | sed -n 's/^\(AS[0-9]\{1,\}\).*/\1/p' | _nbm_trim)"
    fi

    source="ipinfo.io"
  fi

  # --- fallback to myip.com if ipinfo failed ----------------------------
  if [ -z "$public_ipv4" ] || [ -z "$country" ]; then
    local myip
    myip="$(_nbm_fetch_url "https://api.myip.com")"

    if [ -n "$myip" ]; then
      public_ipv4="${public_ipv4:-$(echo "$myip" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | _nbm_trim)}"
      country="${country:-$(echo "$myip" | sed -n 's/.*"cc"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | _nbm_trim)}"
      source="myip.com"
    fi
  fi

  # --- DNS resolvers from system config --------------------------------
  # v0.1 uses exact array comparison (order-sensitive).
  # A future version should sort before comparing to avoid false drift.
  local dns_state raw_dns
  dns_state="$(scutil --dns 2>/dev/null)"
  raw_dns="$(echo "$dns_state" | awk '/nameserver\[[0-9]+\] :/ {print $3}' | awk '!seen[$0]++')"

  if [ -n "$raw_dns" ]; then
    dns_resolver_json="["
    local first=1
    while IFS= read -r dns_ip; do
      [ -z "$dns_ip" ] && continue
      if [ "$first" -eq 1 ]; then
        dns_resolver_json="${dns_resolver_json}\"$dns_ip\""
        first=0
      else
        dns_resolver_json="${dns_resolver_json},\"$dns_ip\""
      fi
    done <<< "$raw_dns"
    dns_resolver_json="${dns_resolver_json}]"
  else
    dns_resolver_json="[]"
  fi

  # --- IPv6 availability -------------------------------------------------
  if ifconfig -l 2>/dev/null | tr ' ' '\n' | while read -r dev; do
    [ -z "$dev" ] && continue
    ifconfig "$dev" 2>/dev/null | grep -q 'inet6 .*[^f][^e]80:' && exit 0
  done; then
    ipv6_available="true"
  fi

  # collected_at = snapshot time.
  # trusted_at is set later by nbm-trust.sh when the user confirms the baseline.
  # --- emit JSON ---------------------------------------------------------
  cat <<JSONEOF
{
  "public_ipv4": "${public_ipv4:-null}",
  "country": "${country:-null}",
  "region": "${region:-null}",
  "asn": "${asn:-null}",
  "isp": "${isp:-null}",
  "dns_resolver": ${dns_resolver_json},
  "ipv6_available": ${ipv6_available},
  "collected_at": "${now}",
  "source": "${source:-unknown}"
}
JSONEOF
}

# ---- file I/O ----------------------------------------------------------

nbm_snapshot_save() {
  local dir
  dir="$(dirname "$NBM_SNAPSHOT_FILE")"
  mkdir -p "$dir" 2>/dev/null
  nbm_snapshot_collect > "$NBM_SNAPSHOT_FILE"
  if [ $? -eq 0 ]; then
    echo "Baseline saved to $NBM_SNAPSHOT_FILE" >&2
    return 0
  else
    echo "Failed to save baseline" >&2
    return 1
  fi
}

nbm_snapshot_load() {
  if [ -f "$NBM_SNAPSHOT_FILE" ]; then
    cat "$NBM_SNAPSHOT_FILE"
    return 0
  else
    echo "No baseline found at $NBM_SNAPSHOT_FILE" >&2
    return 1
  fi
}

# ---- direct invocation ------------------------------------------------
# Only run when executed directly, not when sourced.
if [[ -n "${ZSH_EVAL_CONTEXT:-}" ]]; then
  # zsh: "toplevel" (exact) means direct execution.
  # "toplevel:file" means sourced from another toplevel script.
  if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
    case "${1:-}" in
      save) nbm_snapshot_save ;;
      load) nbm_snapshot_load ;;
      *)    nbm_snapshot_collect ;;
    esac
  fi
elif [[ "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  # bash: script path matches running path
  case "${1:-}" in
    save) nbm_snapshot_save ;;
    load) nbm_snapshot_load ;;
    *)    nbm_snapshot_collect ;;
  esac
fi
