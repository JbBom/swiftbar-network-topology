#!/bin/zsh
#
# System consistency baseline for AI Environment Guard.
#
# Commands:
#   snapshot                 Print current local system facts as JSON.
#   trust [--yes] [--force]  Save the current facts as the trusted baseline.
#   check [--json|--human]   Compare current facts with the trusted baseline.
#
# Exit codes for check:
#   0 = stable
#   1 = drift detected
#   2 = no baseline or collection error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-common.sh"

: "${AEG_SYSTEM_BASELINE_FILE:=$AEG_STATE_DIR/system-baseline.json}"

_aeg_system_string() {
  local value="$1"
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' "unknown"
}

_aeg_system_timezone() {
  local timezone
  timezone="$(readlink /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p')"
  [ -n "$timezone" ] || timezone="$(date +%Z 2>/dev/null)"
  _aeg_system_string "$timezone"
}

_aeg_system_locale() {
  local locale
  locale="$(defaults read -g AppleLocale 2>/dev/null)"
  [ -n "$locale" ] || locale="${LANG:-}"
  _aeg_system_string "$locale"
}

_aeg_system_primary_interface() {
  local interface
  interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  _aeg_system_string "$interface"
}

_aeg_system_proxy_enabled() {
  if scutil --proxy 2>/dev/null | grep -Eq '^(  )?(HTTP|HTTPS|SOCKS)Enable : 1$'; then
    printf 'true'
  else
    printf 'false'
  fi
}

_aeg_system_json_string() {
  local key="$1"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_aeg_system_json_bool() {
  local key="$1"
  sed -n -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(true\).*/\1/p' \
         -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(false\).*/\1/p' | head -1
}

aeg_system_snapshot() {
  local os_version architecture timezone locale primary_interface proxy_enabled collected_at
  os_version="${AEG_SYSTEM_OS_VERSION:-$(sw_vers -productVersion 2>/dev/null)}"
  architecture="${AEG_SYSTEM_ARCHITECTURE:-$(uname -m 2>/dev/null)}"
  timezone="${AEG_SYSTEM_TIMEZONE:-$(_aeg_system_timezone)}"
  locale="${AEG_SYSTEM_LOCALE:-$(_aeg_system_locale)}"
  primary_interface="${AEG_SYSTEM_PRIMARY_INTERFACE:-$(_aeg_system_primary_interface)}"
  proxy_enabled="${AEG_SYSTEM_PROXY_ENABLED:-$(_aeg_system_proxy_enabled)}"
  collected_at="$(aeg_now_utc)"

  printf '{"version":1,"os_version":%s,"architecture":%s,"timezone":%s,"locale":%s,"primary_interface":%s,"system_proxy_enabled":%s,"collected_at":%s}\n' \
    "$(aeg_json_quote "$(_aeg_system_string "$os_version")")" \
    "$(aeg_json_quote "$(_aeg_system_string "$architecture")")" \
    "$(aeg_json_quote "$(_aeg_system_string "$timezone")")" \
    "$(aeg_json_quote "$(_aeg_system_string "$locale")")" \
    "$(aeg_json_quote "$(_aeg_system_string "$primary_interface")")" \
    "$proxy_enabled" \
    "$(aeg_json_quote "$collected_at")"
}

aeg_system_trust() {
  local assume_yes=false force=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) assume_yes=true ;;
      --force) force=true ;;
      -h|--help)
        echo "Usage: aeg-system.sh trust [--yes] [--force]"
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 2
        ;;
    esac
    shift
  done

  if [ -f "$AEG_SYSTEM_BASELINE_FILE" ] && [ "$force" != true ]; then
    echo "System baseline already exists: $AEG_SYSTEM_BASELINE_FILE" >&2
    echo "Use --force to replace it." >&2
    return 2
  fi
  if [ "$assume_yes" != true ]; then
    printf 'Save the current system environment as trusted? [y/N] '
    read -r reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *) echo "Cancelled."; return 1 ;;
    esac
  fi

  mkdir -p "$(dirname "$AEG_SYSTEM_BASELINE_FILE")" || return 2
  local snapshot tmp_file
  snapshot="$(aeg_system_snapshot)" || return 2
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/aeg-system.XXXXXX")" || return 2
  printf '%s\n' "$snapshot" > "$tmp_file"
  mv "$tmp_file" "$AEG_SYSTEM_BASELINE_FILE"
  echo "System baseline saved: $AEG_SYSTEM_BASELINE_FILE"
}

aeg_system_check() {
  local mode="human"
  case "${1:-}" in
    --json) mode="json" ;;
    --human|"") ;;
    -h|--help)
      echo "Usage: aeg-system.sh check [--json|--human]"
      return 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      return 2
      ;;
  esac

  if [ ! -f "$AEG_SYSTEM_BASELINE_FILE" ]; then
    if [ "$mode" = "json" ]; then
      echo '{"status":"error","error":"no system baseline found"}'
    else
      echo "No system baseline found: $AEG_SYSTEM_BASELINE_FILE" >&2
    fi
    return 2
  fi

  local baseline current changes="" change_count=0
  baseline="$(cat "$AEG_SYSTEM_BASELINE_FILE")"
  current="$(aeg_system_snapshot)" || return 2

  _aeg_system_compare() {
    local field="$1" old="$2" new="$3"
    if [ "$old" != "$new" ]; then
      change_count=$((change_count + 1))
      if [ "$mode" = "json" ]; then
        [ -n "$changes" ] && changes="$changes,"
        changes="$changes{\"field\":\"$field\",\"old\":\"$old\",\"new\":\"$new\"}"
      else
        changes="${changes}  ${field}: ${old} -> ${new}"$'\n'
      fi
    fi
  }

  local field old new
  for field in os_version architecture timezone locale primary_interface; do
    old="$(printf '%s' "$baseline" | _aeg_system_json_string "$field")"
    new="$(printf '%s' "$current" | _aeg_system_json_string "$field")"
    _aeg_system_compare "$field" "$old" "$new"
  done
  old="$(printf '%s' "$baseline" | _aeg_system_json_bool "system_proxy_enabled")"
  new="$(printf '%s' "$current" | _aeg_system_json_bool "system_proxy_enabled")"
  _aeg_system_compare "system_proxy_enabled" "$old" "$new"

  if [ "$mode" = "json" ]; then
    if [ "$change_count" -eq 0 ]; then
      echo '{"status":"stable","changes":[]}'
    else
      echo "{\"status\":\"drift\",\"changes\":[$changes]}"
    fi
  elif [ "$change_count" -eq 0 ]; then
    echo "System consistency: stable"
  else
    echo "System consistency drift detected:"
    printf '%s' "$changes"
  fi

  [ "$change_count" -eq 0 ] && return 0 || return 1
}

aeg_system_main() {
  local command="${1:-check}"
  shift 2>/dev/null || true
  case "$command" in
    snapshot) aeg_system_snapshot "$@" ;;
    trust) aeg_system_trust "$@" ;;
    check) aeg_system_check "$@" ;;
    -h|--help)
      echo "Usage: aeg-system.sh <snapshot|trust|check> [options]"
      ;;
    *)
      echo "Unknown command: $command" >&2
      return 2
      ;;
  esac
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_system_main "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_system_main "$@"
fi
