#!/bin/sh
# Diagnostics for Xiaomi Router 7-Day Refresh dual topology modes.

CONFIG="${CONFIG:-/data/xiaomi-router-7day-refresh.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

APP_NAME="${APP_NAME:-xiaomi-router-7day-refresh}"
TOPOLOGY_MODE="${TOPOLOGY_MODE:-unknown}"
IPHONE_MAC="${IPHONE_MAC:-}"
LANIF="${LANIF:-br-lan}"
TARGET="${TARGET:-10.7.0.1}"
ROUTER_LAN_IP="${ROUTER_LAN_IP:-}"
UPSTREAM_GATEWAY="${UPSTREAM_GATEWAY:-}"
LOG="${LOG:-/tmp/$APP_NAME.log}"
DHCP_LOG="${DHCP_LOG:-/tmp/$APP_NAME-dhcp.log}"
STATUS="/data/$APP_NAME-status.sh"

usage() {
  cat <<EOF2
Usage: $0 [status|watch|watch-dhcp|watch-target|logs]

  status       Show service status
  watch        Watch DHCP plus SideStore target traffic on $LANIF
  watch-dhcp   Watch DHCP requests/ACKs
  watch-target Watch traffic to/from $TARGET
  logs         Tail reflector and DHCP injector logs
EOF2
}

need_tcpdump() { command -v tcpdump >/dev/null 2>&1 || { echo "[ERROR] tcpdump not installed" >&2; exit 1; }; }

case "${1:-status}" in
  status)
    exec "$STATUS"
    ;;
  watch)
    need_tcpdump
    echo "Topology: $TOPOLOGY_MODE"
    echo "Watching DHCP and target $TARGET on $LANIF. Press Ctrl+C to stop."
    exec tcpdump -ni "$LANIF" -e -vv "(udp port 67 or udp port 68) or host $TARGET"
    ;;
  watch-dhcp)
    need_tcpdump
    echo "Watching DHCP on $LANIF for iPhone MAC $IPHONE_MAC. Press Ctrl+C to stop."
    exec tcpdump -ni "$LANIF" -e -vvv -s 0 'udp port 67 or udp port 68'
    ;;
  watch-target)
    need_tcpdump
    echo "Watching SideStore override target $TARGET on $LANIF. Press Ctrl+C to stop."
    exec tcpdump -ni "$LANIF" -e -vv "host $TARGET"
    ;;
  logs)
    echo "=== Reflector: $LOG ==="
    tail -30 "$LOG" 2>/dev/null || true
    echo
    echo "=== DHCP injector: $DHCP_LOG ==="
    tail -30 "$DHCP_LOG" 2>/dev/null || true
    ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
