#!/bin/sh
# Stop Xiaomi Router 7-Day Refresh and clean both topology modes.

CONFIG="${CONFIG:-/data/xiaomi-router-7day-refresh.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

APP_NAME="${APP_NAME:-xiaomi-router-7day-refresh}"
IFACE="${IFACE:-sidestore}"
TARGET="${TARGET:-10.7.0.1}"
DNSMASQ_CONF_DIR="${DNSMASQ_CONF_DIR:-}"
REFLECTOR_PIDFILE="${REFLECTOR_PIDFILE:-/tmp/$APP_NAME.pid}"
DHCP_PIDFILE="${DHCP_PIDFILE:-/tmp/$APP_NAME-dhcp.pid}"
DHCP_CHAIN="${DHCP_CHAIN:-XRR_DHCP121}"
REFLECT_CHAIN="${REFLECT_CHAIN:-XRR_REFLECT}"
LANIF="${LANIF:-br-lan}"
DNSMASQ_SNIPPET_NAME="${DNSMASQ_SNIPPET_NAME:-$APP_NAME.conf}"
LEGACY_TARGET="198.19.0.2"

kill_pidfile() {
  pf="$1"
  [ -f "$pf" ] || return 0
  pid="$(cat "$pf" 2>/dev/null || true)"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  n=0
  while [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$n" -lt 5 ]; do sleep 1; n=$((n+1)); done
  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
  rm -f "$pf"
}

remove_chain() {
  chain="$1"
  while iptables -D FORWARD -j "$chain" 2>/dev/null; do :; done
  iptables -F "$chain" 2>/dev/null || true
  iptables -X "$chain" 2>/dev/null || true
}

restart_dnsmasq() {
  if [ -x /etc/init.d/dnsmasq ]; then /etc/init.d/dnsmasq restart
  elif command -v service >/dev/null 2>&1; then service dnsmasq restart
  else return 1
  fi
}

# Remove bridge/DHCP interception before stopping the injector to avoid a DHCP black-hole.
remove_chain "$DHCP_CHAIN"
remove_chain "$REFLECT_CHAIN"
for t in "$TARGET" "$LEGACY_TARGET"; do
  while iptables -t nat -D PREROUTING -i "$LANIF" -d "$t" -j RETURN 2>/dev/null; do :; done
  while iptables -t mangle -D PREROUTING -i "$LANIF" -d "$t" -j ACCEPT 2>/dev/null; do :; done
done
kill_pidfile "$DHCP_PIDFILE"

# Remove only our dnsmasq snippet, wherever the active OpenWrt dnsmasq instance placed its conf-dir.
removed=0
for d in "$DNSMASQ_CONF_DIR" /tmp/dnsmasq.d /tmp/dnsmasq.*.d; do
  [ -n "$d" ] || continue
  f="$d/$DNSMASQ_SNIPPET_NAME"
  if [ -f "$f" ]; then rm -f "$f" && removed=1; fi
done
[ "$removed" -eq 0 ] || restart_dnsmasq >/dev/null 2>&1 || true

for t in "$TARGET" "$LEGACY_TARGET"; do
  ip route del "$t/32" dev "$IFACE" 2>/dev/null || true
done
kill_pidfile "$REFLECTOR_PIDFILE"
ip link del "$IFACE" 2>/dev/null || true

echo "[OK] Xiaomi Router 7-Day Refresh stopped and cleaned."
