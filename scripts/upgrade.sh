#!/bin/sh
# Upgrade/reconfigure to v0.5.1 public dual-topology Override Peer release.
# Intentionally interactive because v0.4 used the experimental 198.19.0.2 target; v0.5 uses Override Peer 10.7.0.1.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
CONFIG="${CONFIG:-/data/xiaomi-router-7day-refresh.conf}"

if [ -f "$CONFIG" ]; then
  BACKUP="$CONFIG.pre-v051.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
  cp "$CONFIG" "$BACKUP"
  echo "[OK] existing config backed up: $BACKUP"
fi

echo "[INFO] Starting interactive migration to target 10.7.0.1."
echo "[INFO] Choose whether this router is the main router or a wireless repeater/child router."
exec sh "$SCRIPT_DIR/install.sh"
