#!/bin/zsh
#
# Read-only AI environment check intended for use before starting an AI CLI.
#
# Exit codes:
#   0 = ready
#   1 = caution or unknown; review before starting
#   2 = alert; pause requests and restore the trusted environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-assess.sh"

aeg_preflight() {
  local mode="human"
  local -a assessment_args

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        mode="json"
        shift
        ;;
      --human)
        mode="human"
        shift
        ;;
      --network-json)
        if [ "$#" -lt 2 ]; then
          echo "--network-json requires a JSON value" >&2
          return 2
        fi
        assessment_args+=(--network-json "$2")
        shift 2
        ;;
      -h|--help)
        echo "Usage: aeg-preflight.sh [--json|--human] [--network-json JSON]"
        echo ""
        echo "Read-only AI environment check before starting an AI CLI."
        echo "Exit codes: 0 = ready, 1 = caution/unknown, 2 = alert"
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 2
        ;;
    esac
  done

  local assessment_output assessment_rc
  if [ "$mode" = "json" ]; then
    assessment_output="$(aeg_assess --json "${assessment_args[@]}")"
  else
    assessment_output="$(aeg_assess --human "${assessment_args[@]}")"
  fi
  assessment_rc=$?

  if [ "$mode" = "json" ]; then
    printf '%s\n' "$assessment_output"
    return "$assessment_rc"
  fi

  echo "AI 启动前检查"
  echo ""
  printf '%s\n' "$assessment_output"
  echo ""
  case "$assessment_rc" in
    0) echo "结论：可以启动 AI 工具，并保持环境监测。" ;;
    1) echo "结论：请先确认并处理环境状态，再启动 AI 工具。" ;;
    *) echo "结论：请暂停 AI 请求，恢复可信环境后重新检查。" ;;
  esac
  return "$assessment_rc"
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_preflight "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_preflight "$@"
fi
