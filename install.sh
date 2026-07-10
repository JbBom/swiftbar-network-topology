#!/bin/zsh
set -e

TARGET_DIR="${1:-$HOME/SwiftBarPlugins}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NBM_BIN_DIR="${NBM_BIN_DIR:-$HOME/.nbm/bin}"
NBM_CONFIG_DIR="${NBM_CONFIG_DIR:-$HOME/.nbm/config}"

mkdir -p "$TARGET_DIR"
TARGET_PLUGIN="$TARGET_DIR/network-topology.10s.sh"
if [ -f "$TARGET_DIR/network-topology.optimized.10s.sh" ] && [ ! -f "$TARGET_PLUGIN" ]; then
  TARGET_PLUGIN="$TARGET_DIR/network-topology.optimized.10s.sh"
fi

cp "$SCRIPT_DIR/network-topology.10s.sh" "$TARGET_PLUGIN"
chmod +x "$TARGET_PLUGIN"

if [ -d "$SCRIPT_DIR/scripts" ]; then
  mkdir -p "$NBM_BIN_DIR"
  cp "$SCRIPT_DIR"/scripts/nbm-*.sh "$SCRIPT_DIR"/scripts/aeg-*.sh "$NBM_BIN_DIR/"
  chmod +x "$NBM_BIN_DIR"/nbm-*.sh "$NBM_BIN_DIR"/aeg-*.sh

  mkdir -p "$NBM_CONFIG_DIR"
  cp "$SCRIPT_DIR/config/ai-apps.tsv" "$NBM_CONFIG_DIR/ai-apps.tsv"

  # Remove helpers installed by older versions; SwiftBar scans subdirectories.
  for helper_name in \
    nbm-snapshot.sh nbm-trust.sh nbm-check.sh \
    aeg-common.sh aeg-processes.sh aeg-history.sh aeg-assess.sh; do
    rm -f "$TARGET_DIR/scripts/$helper_name"
  done
  rmdir "$TARGET_DIR/scripts" 2>/dev/null || true
fi

echo "Installed to: $TARGET_PLUGIN"
echo "NBM/AEG helpers installed to: $NBM_BIN_DIR"
echo "AEG app profiles installed to: $NBM_CONFIG_DIR/ai-apps.tsv"
echo "Refresh SwiftBar to load the plugin."
