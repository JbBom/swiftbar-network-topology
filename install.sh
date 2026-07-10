#!/bin/zsh
set -e

TARGET_DIR="${1:-$HOME/SwiftBarPlugins}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$TARGET_DIR"
cp "$SCRIPT_DIR/network-topology.10s.sh" "$TARGET_DIR/network-topology.10s.sh"
chmod +x "$TARGET_DIR/network-topology.10s.sh"

if [ -d "$SCRIPT_DIR/scripts" ]; then
  mkdir -p "$TARGET_DIR/scripts"
  cp "$SCRIPT_DIR"/scripts/nbm-*.sh "$TARGET_DIR/scripts/"
  chmod +x "$TARGET_DIR"/scripts/nbm-*.sh
fi

echo "Installed to: $TARGET_DIR/network-topology.10s.sh"
echo "Refresh SwiftBar to load the plugin."
