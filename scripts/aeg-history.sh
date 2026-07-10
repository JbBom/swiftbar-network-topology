#!/bin/zsh
#
# Append change-only AI Environment Guard assessments to JSONL history.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-common.sh"

_aeg_history_lock_dir() {
  printf '%s' "$AEG_STATE_DIR/.aeg-history.lock"
}

_aeg_history_acquire_lock() {
  local lock_dir owner_pid
  lock_dir="$(_aeg_history_lock_dir)"

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    return 0
  fi

  owner_pid="$(cat "$lock_dir/pid" 2>/dev/null)"
  case "$owner_pid" in
    ""|*[!0-9]*) return 1 ;;
  esac
  if ! kill -0 "$owner_pid" 2>/dev/null; then
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$lock_dir/pid"
      return 0
    fi
  fi
  return 1
}

_aeg_history_release_lock() {
  rm -rf "$(_aeg_history_lock_dir)"
}

_aeg_history_rotate() {
  local max_entries line_count tmp_history
  max_entries="$AEG_HISTORY_MAX_ENTRIES"
  case "$max_entries" in
    ""|*[!0-9]*) max_entries=500 ;;
  esac
  [ "$max_entries" -lt 1 ] && max_entries=1
  [ ! -f "$AEG_HISTORY_FILE" ] && return 0

  line_count="$(wc -l < "$AEG_HISTORY_FILE" | tr -d ' ')"
  if [ "$line_count" -gt "$max_entries" ] 2>/dev/null; then
    tmp_history="$(mktemp "$AEG_STATE_DIR/.aeg-history.XXXXXX")" || return 1
    tail -n "$max_entries" "$AEG_HISTORY_FILE" > "$tmp_history"
    mv "$tmp_history" "$AEG_HISTORY_FILE"
  fi
}

# aeg_history_record <event-json> <fingerprint-source>
# Prints recorded, unchanged, or busy.
aeg_history_record() {
  local event_json="$1"
  local fingerprint_source="$2"
  local fingerprint last_fingerprint tmp_state

  mkdir -p "$AEG_STATE_DIR" || return 1
  if ! _aeg_history_acquire_lock; then
    echo "busy"
    return 0
  fi

  fingerprint="$(printf '%s' "$fingerprint_source" | cksum | awk '{print $1 ":" $2}')"
  last_fingerprint="$(cat "$AEG_LAST_STATE_FILE" 2>/dev/null)"
  if [ "$fingerprint" = "$last_fingerprint" ]; then
    _aeg_history_release_lock
    echo "unchanged"
    return 0
  fi

  printf '%s\n' "$event_json" >> "$AEG_HISTORY_FILE" || {
    _aeg_history_release_lock
    return 1
  }
  _aeg_history_rotate || {
    _aeg_history_release_lock
    return 1
  }

  tmp_state="$(mktemp "$AEG_STATE_DIR/.aeg-state.XXXXXX")" || {
    _aeg_history_release_lock
    return 1
  }
  printf '%s\n' "$fingerprint" > "$tmp_state"
  mv "$tmp_state" "$AEG_LAST_STATE_FILE"

  _aeg_history_release_lock
  echo "recorded"
}

aeg_history_main() {
  local count=20
  case "${1:-}" in
    --tail)
      count="${2:-20}"
      ;;
    -h|--help)
      echo "Usage: aeg-history.sh --tail [count]"
      return 0
      ;;
    "")
      ;;
    *)
      echo "Unknown option: $1" >&2
      return 2
      ;;
  esac

  if [ -f "$AEG_HISTORY_FILE" ]; then
    tail -n "$count" "$AEG_HISTORY_FILE"
  fi
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_history_main "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_history_main "$@"
fi
