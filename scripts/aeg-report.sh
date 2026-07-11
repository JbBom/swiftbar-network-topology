#!/bin/zsh
#
# Produce a local, read-only diagnostic report for AI Environment Guard.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/aeg-assess.sh"
source "$SCRIPT_DIR/nbm-snapshot.sh"

_aeg_report_json_string() {
  local key="$1"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_aeg_report_json_bool() {
  local key="$1"
  sed -n -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(true\).*/\1/p' \
         -e 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(false\).*/\1/p' | head -1
}

_aeg_report_json_dns() {
  sed -n 's/.*"dns_resolver"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' |
    sed 's/"[[:space:]]*,[[:space:]]*"/, /g; s/"//g' | head -1
}

_aeg_report_history_line() {
  local event="$1"
  local checked_at event_status reason apps
  checked_at="$(printf '%s' "$event" | _aeg_report_json_string "checked_at")"
  event_status="$(printf '%s' "$event" | awk -F'"status":"' 'NF > 1 { split($2, value, "\""); print value[1]; exit }')"
  reason="$(printf '%s' "$event" | sed -n 's/.*"reasons":\[{"code":"[^"]*","message":"\([^"]*\)"}.*/\1/p' | head -1)"
  apps="$(printf '%s' "$event" | grep -o '"label":"[^"]*"' | sed 's/^"label":"//; s/"$//' | paste -sd '、' -)"
  [ -z "$apps" ] && apps="未检测到"
  printf '%s | %s | %s | %s\n' "${checked_at:-unknown}" "${event_status:-unknown}" "${reason:-unknown}" "$apps"
}

aeg_report() {
  local tail_count=10
  local network_json=""
  local -a assessment_args

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tail)
        if [ "$#" -lt 2 ] || [[ "$2" != <-> ]] || [ "$2" -lt 1 ]; then
          echo "--tail requires a positive integer" >&2
          return 2
        fi
        tail_count="$2"
        shift 2
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
        echo "Usage: aeg-report.sh [--tail COUNT] [--network-json JSON]"
        echo ""
        echo "Prints a local diagnostic report. Default history count: 10."
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 2
        ;;
    esac
  done

  [ -n "$network_json" ] && assessment_args+=(--network-json "$network_json")
  local assessment assessment_rc baseline
  assessment="$(aeg_assess --human "${assessment_args[@]}")"
  assessment_rc=$?

  echo "AI Environment Guard 诊断报告"
  echo "生成时间：$(aeg_now_utc)"
  echo ""
  echo "当前环境"
  printf '%s\n' "$assessment"
  echo ""
  echo "可信网络基线"
  baseline="$(nbm_snapshot_load 2>/dev/null)"
  if [ -z "$baseline" ]; then
    echo "⚪ 尚未建立可信基线"
  else
    echo "公网 IPv4：$(printf '%s' "$baseline" | _aeg_report_json_string "public_ipv4")"
    echo "国家/地区：$(printf '%s' "$baseline" | _aeg_report_json_string "country")"
    echo "ASN：$(printf '%s' "$baseline" | _aeg_report_json_string "asn")"
    echo "DNS：$(printf '%s' "$baseline" | _aeg_report_json_dns)"
    echo "IPv6：$(printf '%s' "$baseline" | _aeg_report_json_bool "ipv6_available")"
    echo "确认时间：$(printf '%s' "$baseline" | _aeg_report_json_string "trusted_at")"
  fi
  echo ""
  echo "最近状态变化（时间 | 状态 | 原因 | 运行中的 AI）"
  if [ -f "$AEG_HISTORY_FILE" ] && [ -s "$AEG_HISTORY_FILE" ]; then
    while IFS= read -r event; do
      [ -n "$event" ] && _aeg_report_history_line "$event"
    done < <(tail -n "$tail_count" "$AEG_HISTORY_FILE")
  else
    echo "暂无历史记录"
  fi

  return "$assessment_rc"
}

if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
  aeg_report "$@"
elif [[ -z "${ZSH_EVAL_CONTEXT:-}" && "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  aeg_report "$@"
fi
