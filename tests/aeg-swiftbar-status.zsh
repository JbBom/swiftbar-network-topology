#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_OUTPUT="$(zsh "$ROOT_DIR/network-topology.10s.sh")"
MENU_BAR_TITLE="$(printf '%s\n' "$PLUGIN_OUTPUT" | sed -n '1p')"

if ! printf '%s\n' "$MENU_BAR_TITLE" | grep -Eq '^(🟢|🟡|🚨|⚪)'; then
  echo "SwiftBar title does not start with the AEG status icon: $MENU_BAR_TITLE" >&2
  exit 1
fi

if printf '%s\n' "$PLUGIN_OUTPUT" | grep -q '^⚪ AI 环境：功能不可用$'; then
  echo "SwiftBar marked AEG unavailable even though the helper is present." >&2
  exit 1
fi

if ! printf '%s\n' "$PLUGIN_OUTPUT" | grep -Eq '^(🟢 AI 环境：可以运行|🟡 AI 环境：需要确认|🚨 AI 环境：请处理|⚪ AI 环境：无法判断)$'; then
  echo "SwiftBar did not render a valid AEG state." >&2
  exit 1
fi

if ! printf '%s\n' "$PLUGIN_OUTPUT" | grep -Eq '^(🟢 系统一致性：稳定|🟡 系统一致性：发生变化|⚪ 系统一致性：(未建立|功能不可用))$'; then
  echo "SwiftBar did not render a valid system consistency state." >&2
  exit 1
fi

if ! printf '%s\n' "$PLUGIN_OUTPUT" | grep -q '^📄 导出环境诊断报告 | '; then
  echo "SwiftBar diagnostic export action is missing." >&2
  exit 1
fi

echo "aeg SwiftBar status checks passed"
