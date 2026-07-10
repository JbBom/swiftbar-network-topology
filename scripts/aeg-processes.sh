#!/bin/zsh
#
# Detect configured AI applications from the local process list.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-common.sh"

aeg_process_source() {
  if [ -n "${AEG_PROCESS_SOURCE_FILE:-}" ]; then
    cat "$AEG_PROCESS_SOURCE_FILE"
  else
    ps -axo pid=,command=
  fi
}

# Emits tab-separated rows: app_id, label, comma-separated PIDs.
aeg_detect_processes() {
  if [ ! -f "$AEG_PROFILES_FILE" ]; then
    echo "AI app profile file not found: $AEG_PROFILES_FILE" >&2
    return 2
  fi

  local process_list app_id label pattern exclude_pattern pids
  process_list="$(aeg_process_source)"

  while IFS=$'\t' read -r app_id label pattern exclude_pattern; do
    case "$app_id" in
      ""|\#*) continue ;;
    esac
    [ -z "$pattern" ] && continue

    pids="$(printf '%s\n' "$process_list" | awk \
      -v regex="$pattern" \
      -v exclude="$exclude_pattern" \
      -v self_pid="$$" \
      '
        {
          pid = $1
          $1 = ""
          command = tolower($0)
          if (pid != self_pid && command ~ regex &&
              (exclude == "" || command !~ exclude)) {
            print pid
          }
        }
      ' | paste -sd, -)"

    if [ -n "$pids" ]; then
      printf '%s\t%s\t%s\n' "$app_id" "$label" "$pids"
    fi
  done < "$AEG_PROFILES_FILE"
}

aeg_process_rows_to_json() {
  local rows="$1"
  local app_id label pids first=true

  printf '['
  if [ -n "$rows" ]; then
    while IFS=$'\t' read -r app_id label pids; do
      [ -z "$app_id" ] && continue
      if [ "$first" = true ]; then
        first=false
      else
        printf ','
      fi
      printf '{"id":%s,"label":%s,"pids":[%s]}' \
        "$(aeg_json_quote "$app_id")" \
        "$(aeg_json_quote "$label")" \
        "$pids"
    done <<< "$rows"
  fi
  printf ']'
}

aeg_detect_processes_json() {
  local rows
  rows="$(aeg_detect_processes)" || return $?
  aeg_process_rows_to_json "$rows"
  printf '\n'
}

aeg_processes_main() {
  local mode="human"
  case "${1:-}" in
    --json) mode="json" ;;
    --tsv) mode="tsv" ;;
    -h|--help)
      echo "Usage: aeg-processes.sh [--json|--tsv]"
      return 0
      ;;
    "") ;;
    *)
      echo "Unknown option: $1" >&2
      return 2
      ;;
  esac

  local rows
  rows="$(aeg_detect_processes)" || return $?

  case "$mode" in
    json)
      aeg_process_rows_to_json "$rows"
      printf '\n'
      ;;
    tsv)
      [ -n "$rows" ] && printf '%s\n' "$rows"
      ;;
    human)
      if [ -z "$rows" ]; then
        echo "未检测到正在运行的受监测 AI 软件。"
      else
        while IFS=$'\t' read -r app_id label pids; do
          echo "$label：PID $pids"
        done <<< "$rows"
      fi
      ;;
  esac
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_processes_main "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_processes_main "$@"
fi
