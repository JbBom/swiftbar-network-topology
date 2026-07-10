#!/bin/zsh
set -e

TARGET_DIR="${1:-$HOME/SwiftBarPlugins}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NBM_BIN_DIR="${NBM_BIN_DIR:-$HOME/.nbm/bin}"

mkdir -p "$TARGET_DIR"
TARGET_PLUGIN="$TARGET_DIR/network-topology.10s.sh"
if [ -f "$TARGET_DIR/network-topology.optimized.10s.sh" ] && [ ! -f "$TARGET_PLUGIN" ]; then
  TARGET_PLUGIN="$TARGET_DIR/network-topology.optimized.10s.sh"
fi

cp "$SCRIPT_DIR/network-topology.10s.sh" "$TARGET_PLUGIN"
chmod +x "$TARGET_PLUGIN"

if [ -d "$SCRIPT_DIR/scripts" ]; then
  mkdir -p "$NBM_BIN_DIR"
  cp "$SCRIPT_DIR"/scripts/nbm-*.sh "$NBM_BIN_DIR/"
  chmod +x "$NBM_BIN_DIR"/nbm-*.sh

  # Remove helpers installed by older versions; SwiftBar scans subdirectories.
  rm -f "$TARGET_DIR"/scripts/nbm-snapshot.sh
  rm -f "$TARGET_DIR"/scripts/nbm-trust.sh
  rm -f "$TARGET_DIR"/scripts/nbm-check.sh
  rmdir "$TARGET_DIR/scripts" 2>/dev/null || true
fi

echo "Installed to: $TARGET_PLUGIN"
echo "NBM helpers installed to: $NBM_BIN_DIR"
echo "Refresh SwiftBar to load the plugin."
