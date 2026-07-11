#!/bin/zsh
#
# nbm-check.sh — Network Baseline Monitor: drift detection
#
# Compares the current network state against the trusted baseline
# and reports whether drift has occurred.
#
# Usage:
#   ./scripts/nbm-check.sh              # human-readable output
#   ./scripts/nbm-check.sh --json       # machine-readable JSON
#   ./scripts/nbm-check.sh --current-env # use caller-provided current state
#   ./scripts/nbm-check.sh --help
#
# Source:
#   source scripts/nbm-check.sh
#   nbm_check --json
#
# Exit codes:
#   0 = stable (no drift detected)
#   1 = drift detected (one or more fields changed)
#   2 = no baseline found or error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/nbm-snapshot.sh"

# ---- helpers ------------------------------------------------------------

# Extract a scalar JSON value by key from stdin.
# Usage: echo "$json" | _nbm_json_get "key"
_nbm_json_get() {
  local key="$1"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Extract a boolean JSON value by key from stdin.
# Usage: echo "$json" | _nbm_json_get_bool "key"
_nbm_json_get_bool() {
  local key="$1"
  sed -n \
    -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(true\).*/\1/p' \
    -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(false\).*/\1/p' | head -1
}

# Extract the dns_resolver array as a compact JSON string.
# Usage: echo "$json" | _nbm_json_get_dns
_nbm_json_get_dns() {
  sed -n 's/.*"dns_resolver"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p' | head -1
}

# ---- check function -----------------------------------------------------

# nbm_check [--json] [--human] [--current-env]
# --json         output machine-readable JSON
# --human        output human-readable text (default)
# --current-env  compare caller-provided NBM_CURRENT_* values
#
# Exit codes: 0 = stable, 1 = drift, 2 = missing baseline / error
nbm_check() {
  local mode="human"
  local use_current_env=false

  for arg in "$@"; do
    case "$arg" in
      --json)        mode="json" ;;
      --human)       mode="human" ;;
      --current-env) use_current_env=true ;;
      -h|--help)
        echo "Usage: nbm_check [--json] [--human] [--current-env]"
        echo ""
        echo "  --json         Machine-readable JSON output"
        echo "  --human        Human-readable text output (default)"
        echo "  --current-env  Use NBM_CURRENT_* values instead of collecting again"
        echo ""
        echo "Exit codes: 0 = stable, 1 = drift, 2 = no baseline or error"
        return 0
        ;;
      *)
        echo "Unknown option: $arg" >&2
        return 2
        ;;
    esac
  done

  # --- load baseline ---
  if [ ! -f "$NBM_SNAPSHOT_FILE" ]; then
    if [ "$mode" = "json" ]; then
      echo '{"status":"error","error":"no baseline found"}'
    else
      echo "No baseline found at $NBM_SNAPSHOT_FILE" >&2
      echo "Run nbm-trust.sh --yes first." >&2
    fi
    return 2
  fi

  local baseline current
  baseline="$(cat "$NBM_SNAPSHOT_FILE")"

  # --- collect current state ---
  if [ "$use_current_env" = true ]; then
    if [ "${NBM_CURRENT_STATE_READY:-}" != "1" ] ||
       [ -z "${NBM_CURRENT_PUBLIC_IPV4+x}" ] ||
       [ -z "${NBM_CURRENT_COUNTRY+x}" ] ||
       [ -z "${NBM_CURRENT_ASN+x}" ] ||
       [ -z "${NBM_CURRENT_DNS_RESOLVER+x}" ] ||
       [ -z "${NBM_CURRENT_IPV6_AVAILABLE+x}" ]; then
      if [ "$mode" = "json" ]; then
        echo '{"status":"error","error":"current state environment incomplete"}'
      else
        echo "Current network state was not provided by the caller." >&2
      fi
      return 2
    fi

    local -a unavailable_fields
    unavailable_fields=()
    [ "$NBM_CURRENT_PUBLIC_IPV4" = "null" ] && unavailable_fields+=("public_ipv4")
    [ "$NBM_CURRENT_COUNTRY" = "null" ] && unavailable_fields+=("country")
    [ "$NBM_CURRENT_ASN" = "null" ] && unavailable_fields+=("asn")
    if [ ${#unavailable_fields[@]} -gt 0 ]; then
      if [ "$mode" = "json" ]; then
        local unavailable_json
        unavailable_json="$(printf '"%s",' "${unavailable_fields[@]}")"
        unavailable_json="[${unavailable_json%,}]"
        echo "{\"status\":\"error\",\"error\":\"current state environment incomplete\",\"unavailable_fields\":$unavailable_json}"
      else
        echo "Current network state is incomplete: ${unavailable_fields[*]}." >&2
      fi
      return 2
    fi
  else
    local tmp_current
    tmp_current="$(mktemp "${TMPDIR:-/tmp}/nbm-check.XXXXXX")" || {
      echo "Failed to create temporary current-state file." >&2
      return 2
    }
    trap "rm -f '$tmp_current'" EXIT
    nbm_snapshot_collect > "$tmp_current"
    current="$(cat "$tmp_current")"
  fi

  # --- compare fields ---
  # Fields to compare: public_ipv4, country, asn, dns_resolver, ipv6_available
  local changes=""
  local change_count=0

  _nbm_compare() {
    local field="$1" old="$2" new="$3"
    if [ "$old" != "$new" ]; then
      change_count=$((change_count + 1))
      if [ "$mode" = "json" ]; then
        if [ -n "$changes" ]; then
          changes="$changes,"
        fi
        # JSON-escape values for embedding
        local old_esc new_esc
        old_esc="$(echo "$old" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        new_esc="$(echo "$new" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        changes="$changes{\"field\":\"$field\",\"old\":\"$old_esc\",\"new\":\"$new_esc\"}"
      else
        changes="$changes  $field: $old -> $new"$'\n'
      fi
    fi
  }

  local b_ip b_country b_asn b_dns b_ipv6
  local c_ip c_country c_asn c_dns c_ipv6

  b_ip="$(echo "$baseline" | _nbm_json_get "public_ipv4")"
  b_country="$(echo "$baseline" | _nbm_json_get "country")"
  b_asn="$(echo "$baseline" | _nbm_json_get "asn")"
  b_dns="$(echo "$baseline" | _nbm_json_get_dns)"
  b_ipv6="$(echo "$baseline" | _nbm_json_get_bool "ipv6_available")"

  if [ "$use_current_env" = true ]; then
    c_ip="${NBM_CURRENT_PUBLIC_IPV4:-null}"
    c_country="${NBM_CURRENT_COUNTRY:-null}"
    c_asn="${NBM_CURRENT_ASN:-null}"
    c_dns="${NBM_CURRENT_DNS_RESOLVER:-[]}"
    c_ipv6="${NBM_CURRENT_IPV6_AVAILABLE:-false}"
  else
    c_ip="$(echo "$current" | _nbm_json_get "public_ipv4")"
    c_country="$(echo "$current" | _nbm_json_get "country")"
    c_asn="$(echo "$current" | _nbm_json_get "asn")"
    c_dns="$(echo "$current" | _nbm_json_get_dns)"
    c_ipv6="$(echo "$current" | _nbm_json_get_bool "ipv6_available")"
  fi

  _nbm_compare "public_ipv4"      "$b_ip"      "$c_ip"
  _nbm_compare "country"          "$b_country"  "$c_country"
  _nbm_compare "asn"              "$b_asn"      "$c_asn"
  _nbm_compare "dns_resolver"     "$b_dns"      "$c_dns"
  _nbm_compare "ipv6_available"   "$b_ipv6"     "$c_ipv6"

  # --- output ---
  if [ "$mode" = "json" ]; then
    if [ "$change_count" -eq 0 ]; then
      echo '{"status":"stable","changes":[]}'
    else
      echo "{\"status\":\"drift\",\"changes\":[$changes]}"
    fi
  else
    if [ "$change_count" -eq 0 ]; then
      echo "Stable — no drift detected."
    else
      echo "Drift detected:"
      printf "%s" "$changes"
    fi
  fi

  if [ "$change_count" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# ---- direct invocation guard --------------------------------------------
# Only call nbm_check when executed directly, not when sourced.
if [[ -n "${ZSH_EVAL_CONTEXT:-}" ]]; then
  # zsh: "toplevel" (exact) means direct execution.
  if [[ "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
    nbm_check "$@"
  fi
elif [[ "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  # bash
  nbm_check "$@"
fi
