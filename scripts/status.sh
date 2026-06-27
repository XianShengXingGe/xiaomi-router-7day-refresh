#!/bin/sh
# Human-readable status check for Xiaomi Router Auto-Sign.

APP_NAME="${APP_NAME:-xiaomi-router-autosign}"
CONFIG="${CONFIG:-/data/$APP_NAME.conf}"

if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

IPHONE="${IPHONE:-192.168.31.100}"
LANIF="${LANIF:-br-lan}"
IFACE="${IFACE:-sidestore}"
TARGET="${TARGET:-10.7.0.1}"
LOG="${LOG:-/tmp/$APP_NAME.log}"

ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }

echo "Xiaomi Router Auto-Sign status"
echo

if ps | grep "$APP_NAME" | grep -v grep >/dev/null 2>&1; then
  ok "helper process is running"
else
  warn "helper process is not running"
fi

if ip link show "$IFACE" >/dev/null 2>&1; then
  ok "TUN interface $IFACE exists"
  if ip link show "$IFACE" 2>/dev/null | grep -q "UP"; then
    ok "TUN interface $IFACE is up"
  else
    warn "TUN interface $IFACE exists but is not up"
  fi
else
  warn "TUN interface $IFACE does not exist"
fi

if ip route get "$TARGET" 2>/dev/null | grep -q "$IFACE"; then
  ok "route to $TARGET uses $IFACE"
else
  warn "route to $TARGET does not use $IFACE"
fi

if iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep -q "$TARGET"; then
  ok "ShellClash bypass rule for $TARGET exists"
else
  warn "ShellClash bypass rule for $TARGET was not found"
fi

if iptables -L FORWARD -n -v 2>/dev/null | grep -q "$IPHONE.*$TARGET"; then
  ok "forward rule from iPhone to $TARGET exists"
else
  warn "forward rule from iPhone to $TARGET was not found"
fi

if [ -f "$LOG" ]; then
  ok "log file exists: $LOG"
  tail -8 "$LOG" 2>/dev/null
else
  warn "log file does not exist yet: $LOG"
fi
