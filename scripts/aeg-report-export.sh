#!/bin/zsh
#
# Export an AEG diagnostic report to a timestamped local text file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-common.sh"

aeg_report_export() {
  local tail_count=10
  case "${1:-}" in
    --tail)
      if [ "$#" -lt 2 ] || [[ "$2" != <-> ]] || [ "$2" -lt 1 ]; then
        echo "--tail requires a positive integer" >&2
        return 2
      fi
      tail_count="$2"
      ;;
    -h|--help)
      echo "Usage: aeg-report-export.sh [--tail COUNT]"
      return 0
      ;;
    "")
      ;;
    *)
      echo "Unknown option: $1" >&2
      return 2
      ;;
  esac

  mkdir -p "$AEG_REPORT_DIR" || return 2
  local timestamp report_file assessment_rc
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  report_file="$AEG_REPORT_DIR/aeg-diagnostic-$timestamp.txt"

  "$SCRIPT_DIR/aeg-report.sh" --tail "$tail_count" > "$report_file"
  assessment_rc=$?
  if [ ! -s "$report_file" ]; then
    echo "Failed to create diagnostic report." >&2
    return 2
  fi

  echo "Diagnostic report created."
  echo "Path: $report_file"
  echo "Assessment exit code: $assessment_rc"
  return 0
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_report_export "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_report_export "$@"
fi
