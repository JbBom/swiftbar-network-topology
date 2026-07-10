#!/bin/zsh
#
# Combine network baseline state with running AI applications.
#
# Exit codes:
#   0 = ready
#   1 = caution or unknown
#   2 = alert

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-common.sh"
source "$SCRIPT_DIR/aeg-processes.sh"
source "$SCRIPT_DIR/aeg-history.sh"

: "${NBM_CHECK_SCRIPT:=$SCRIPT_DIR/nbm-check.sh}"

_aeg_network_status() {
  sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_aeg_assessment_json() {
  local checked_at="$1"
  local result_status="$2"
  local severity="$3"
  local network_json="$4"
  local running_apps_json="$5"
  local reason_code="$6"
  local reason_message="$7"
  local action_code="$8"
  local action_message="$9"

  printf '{"version":1,"checked_at":%s,"status":%s,"severity":%s,"network":%s,"running_apps":%s,"reasons":[{"code":%s,"message":%s}],"actions":[{"code":%s,"message":%s}]}' \
    "$(aeg_json_quote "$checked_at")" \
    "$(aeg_json_quote "$result_status")" \
    "$severity" \
    "$network_json" \
    "$running_apps_json" \
    "$(aeg_json_quote "$reason_code")" \
    "$(aeg_json_quote "$reason_message")" \
    "$(aeg_json_quote "$action_code")" \
    "$(aeg_json_quote "$action_message")"
}

aeg_assess() {
  local mode="human"
  local record=false
  local network_json="${AEG_NETWORK_JSON:-}"

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
      --record)
        record=true
        shift
        ;;
      --network-json)
        if [ "$#" -lt 2 ]; then
          echo "--network-json requires a JSON value" >&2
          return 2
        fi
        network_json="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: aeg-assess.sh [--json|--human] [--record] [--network-json JSON]"
        echo ""
        echo "Exit codes: 0 = ready, 1 = caution/unknown, 2 = alert"
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 2
        ;;
    esac
  done

  if [ -z "$network_json" ]; then
    network_json="$("$NBM_CHECK_SCRIPT" --json)"
  fi
  network_json="$(printf '%s' "$network_json" | tr -d '\n')"

  local network_status
  network_status="$(printf '%s' "$network_json" | _aeg_network_status)"
  case "$network_status" in
    stable|drift|error) ;;
    *)
      network_status="error"
      network_json='{"status":"error","error":"invalid network assessment"}'
      ;;
  esac

  local process_rows process_rc running_apps_json app_count app_ids app_labels
  process_rows="$(aeg_detect_processes 2>/dev/null)"
  process_rc=$?
  if [ "$process_rc" -ne 0 ]; then
    process_rows=""
  fi
  running_apps_json="$(aeg_process_rows_to_json "$process_rows")"
  app_count=0
  app_ids=""
  app_labels=""
  if [ -n "$process_rows" ]; then
    local app_id label pids separator=""
    while IFS=$'\t' read -r app_id label pids; do
      [ -z "$app_id" ] && continue
      app_count=$((app_count + 1))
      app_ids="${app_ids}${separator}${app_id}"
      app_labels="${app_labels}${separator}${label}"
      separator=", "
    done <<< "$process_rows"
  fi

  local assessment_status severity reason_code reason_message action_code action_message
  if [ "$process_rc" -ne 0 ]; then
    assessment_status="unknown"
    severity=2
    reason_code="process_detection_unavailable"
    reason_message="无法读取 AI 软件运行状态。"
    action_code="repair_process_detection"
    action_message="检查 AI 软件配置文件和进程读取权限后重新检测。"
  elif [ "$network_status" = "stable" ]; then
    assessment_status="ready"
    severity=0
    if [ "$app_count" -gt 0 ]; then
      reason_code="environment_stable_while_ai_running"
      reason_message="AI 软件运行中，网络环境与可信基线一致。"
    else
      reason_code="environment_stable"
      reason_message="网络环境与可信基线一致。"
    fi
    action_code="continue_monitoring"
    action_message="可以继续运行，并保持环境监测。"
  elif [ "$network_status" = "drift" ] && [ "$app_count" -gt 0 ]; then
    assessment_status="alert"
    severity=3
    reason_code="network_drift_while_ai_running"
    reason_message="AI 软件运行期间检测到网络环境漂移。"
    action_code="pause_ai_and_restore_network"
    action_message="暂停 AI 请求，检查 VPN 或代理，恢复可信网络后重新检测。"
  elif [ "$network_status" = "drift" ]; then
    assessment_status="caution"
    severity=2
    reason_code="network_drift_before_launch"
    reason_message="当前网络与可信基线不一致。"
    action_code="restore_network_before_launch"
    action_message="先恢复可信网络，再启动 AI 软件。"
  elif [ "$app_count" -gt 0 ]; then
    assessment_status="alert"
    severity=3
    reason_code="network_visibility_lost_while_ai_running"
    reason_message="AI 软件运行中，但当前无法确认网络基线状态。"
    action_code="pause_ai_and_recheck"
    action_message="暂停 AI 请求，修复基线检测后再继续。"
  else
    assessment_status="unknown"
    severity=2
    reason_code="network_baseline_unavailable"
    reason_message="当前无法确认网络基线状态。"
    action_code="establish_or_repair_baseline"
    action_message="建立可信基线或修复网络检测后再启动 AI 软件。"
  fi

  local checked_at assessment_json fingerprint
  checked_at="$(aeg_now_utc)"
  assessment_json="$(_aeg_assessment_json \
    "$checked_at" \
    "$assessment_status" \
    "$severity" \
    "$network_json" \
    "$running_apps_json" \
    "$reason_code" \
    "$reason_message" \
    "$action_code" \
    "$action_message")"
  fingerprint="$assessment_status|$network_json|$app_ids|$reason_code|$action_code"

  if [ "$record" = true ]; then
    aeg_history_record "$assessment_json" "$fingerprint" >/dev/null || {
      echo "Failed to record AI environment history." >&2
    }
  fi

  if [ "$mode" = "json" ]; then
    printf '%s\n' "$assessment_json"
  else
    case "$assessment_status" in
      ready) echo "🟢 AI 环境：可以运行" ;;
      caution) echo "🟡 AI 环境：需要确认" ;;
      alert) echo "🚨 AI 环境：立即处理" ;;
      *) echo "⚪ AI 环境：无法判断" ;;
    esac
    case "$network_status" in
      stable) echo "网络基线：稳定" ;;
      drift) echo "网络基线：发生漂移" ;;
      *) echo "网络基线：不可用" ;;
    esac
    if [ "$app_count" -gt 0 ]; then
      echo "运行中的 AI：$app_labels"
    else
      echo "运行中的 AI：未检测到"
    fi
    echo "原因：$reason_message"
    echo "建议：$action_message"
  fi

  case "$assessment_status" in
    ready) return 0 ;;
    alert) return 2 ;;
    *) return 1 ;;
  esac
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_assess "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_assess "$@"
fi
