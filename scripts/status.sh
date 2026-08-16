#!/bin/sh
# Status for Xiaomi Router 7-Day Refresh - dual topology release.

CONFIG="${CONFIG:-/data/xiaomi-router-7day-refresh.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

APP_NAME="${APP_NAME:-xiaomi-router-7day-refresh}"
TOPOLOGY_MODE="${TOPOLOGY_MODE:-unknown}"
IPHONE_MAC="${IPHONE_MAC:-}"
LANIF="${LANIF:-br-lan}"
ROUTER_LAN_IP="${ROUTER_LAN_IP:-}"
UPSTREAM_GATEWAY="${UPSTREAM_GATEWAY:-}"
DNSMASQ_CONF_DIR="${DNSMASQ_CONF_DIR:-}"
IFACE="${IFACE:-sidestore}"
TARGET="${TARGET:-10.7.0.1}"
APP="${APP:-/data/$APP_NAME}"
LOG="${LOG:-/tmp/$APP_NAME.log}"
DHCP_LOG="${DHCP_LOG:-/tmp/$APP_NAME-dhcp.log}"
REFLECTOR_PIDFILE="${REFLECTOR_PIDFILE:-/tmp/$APP_NAME.pid}"
DHCP_PIDFILE="${DHCP_PIDFILE:-/tmp/$APP_NAME-dhcp.pid}"
DHCP_CHAIN="${DHCP_CHAIN:-XRR_DHCP121}"
REFLECT_CHAIN="${REFLECT_CHAIN:-XRR_REFLECT}"
DNSMASQ_SNIPPET_NAME="${DNSMASQ_SNIPPET_NAME:-$APP_NAME.conf}"

ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; }
info() { echo "[INFO] $*"; }

pid_ok() {
  pf="$1"
  [ -f "$pf" ] || return 1
  pid="$(cat "$pf" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

echo "Xiaomi Router 7-Day Refresh status"
echo "===================================="
echo "Topology        : $TOPOLOGY_MODE"
echo "iPhone MAC      : ${IPHONE_MAC:-none}"
echo "Router LAN IP   : ${ROUTER_LAN_IP:-none}"
echo "Upstream GW     : ${UPSTREAM_GATEWAY:-n/a}"
echo "Override target : $TARGET"
echo "Reflector TUN   : $IFACE"
if [ -x "$APP" ]; then
  VERSION="$($APP -version 2>/dev/null || true)"
  [ -n "$VERSION" ] && echo "Helper version  : $VERSION"
fi
echo

if pid_ok "$REFLECTOR_PIDFILE"; then
  ok "reflector process is running (pid $(cat "$REFLECTOR_PIDFILE"))"
else
  fail "reflector process is not running"
fi
if ip link show "$IFACE" >/dev/null 2>&1; then
  ok "TUN interface $IFACE exists"
else
  fail "TUN interface $IFACE does not exist"
fi
if ip route get "$TARGET" 2>/dev/null | grep -q "$IFACE"; then
  ok "router route $TARGET/32 uses $IFACE"
else
  fail "router route $TARGET/32 does not use $IFACE"
fi
if iptables -L "$REFLECT_CHAIN" -n >/dev/null 2>&1; then
  ok "reflector firewall chain $REFLECT_CHAIN exists"
else
  fail "reflector firewall chain $REFLECT_CHAIN missing"
fi

echo
case "$TOPOLOGY_MODE" in
  main-router)
    echo "Mode 1: main router"
    echo "-------------------"
    command -v dnsmasq >/dev/null 2>&1 && ok "dnsmasq is available" || fail "dnsmasq missing"
    found=""
    for d in "$DNSMASQ_CONF_DIR" /tmp/dnsmasq.d /tmp/dnsmasq.*.d; do
      [ -n "$d" ] || continue
      f="$d/$DNSMASQ_SNIPPET_NAME"
      if [ -f "$f" ]; then found="$f"; break; fi
    done
    if [ -n "$found" ]; then
      ok "targeted DHCP Option121 snippet exists: $found"
      sed 's/^/     /' "$found"
    else
      fail "targeted DHCP Option121 snippet not found"
    fi
    ;;
  wireless-repeater)
    echo "Mode 2: wireless repeater / child router"
    echo "----------------------------------------"
    if pid_ok "$DHCP_PIDFILE"; then
      ok "DHCP121 injector is running (pid $(cat "$DHCP_PIDFILE"))"
    else
      fail "DHCP121 injector is not running"
    fi
    if [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ] && [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null)" = 1 ]; then
      ok "bridge-nf-call-iptables=1"
    else
      fail "bridge-nf-call-iptables is disabled/unavailable"
    fi
    if iptables -L "$DHCP_CHAIN" -n -v -x >/tmp/xrr-status.$$ 2>/dev/null; then
      ok "DHCP ACK interception chain $DHCP_CHAIN exists"
      cat /tmp/xrr-status.$$ | sed 's/^/     /'
    else
      fail "DHCP ACK interception chain $DHCP_CHAIN missing"
    fi
    rm -f /tmp/xrr-status.$$
    if grep -q 'INJECTED DHCP ACK' "$DHCP_LOG" 2>/dev/null; then
      ok "at least one patched DHCP ACK has been injected"
      grep 'INJECTED DHCP ACK' "$DHCP_LOG" | tail -3
    else
      warn "no patched DHCP ACK logged yet; toggle iPhone Wi-Fi OFF/ON once"
      tail -10 "$DHCP_LOG" 2>/dev/null || true
    fi
    ;;
  *) fail "unknown TOPOLOGY_MODE=$TOPOLOGY_MODE" ;;
esac

echo
echo "Recent reflector log"
echo "--------------------"
if grep -q 'reflector rewrote packet #' "$LOG" 2>/dev/null; then
  ok "SideStore override packets have reached the router and been reflected"
  grep 'reflector rewrote packet #' "$LOG" | tail -5
else
  warn "no reflected SideStore packet logged yet"
  tail -10 "$LOG" 2>/dev/null || true
fi

echo
echo "Expected phone route after DHCP:"
echo "  $TARGET/32 -> next-hop $ROUTER_LAN_IP"
echo "If this is the first start, toggle iPhone Wi-Fi OFF/ON once and then try SideStore Refresh."
