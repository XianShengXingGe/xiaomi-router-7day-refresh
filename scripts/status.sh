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

ok() { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; }
info() { echo "[INFO] $*"; }

pid_ok() {
  pf="$1"
  [ -f "$pf" ] || return 1
  pid="$(cat "$pf" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

echo "=================================================="
echo " Xiaomi Router 7-Day Refresh Status"
echo "=================================================="
echo "Topology        : $TOPOLOGY_MODE"
echo "iPhone MAC      : ${IPHONE_MAC:-none}"
echo "Router LAN IP   : ${ROUTER_LAN_IP:-none}"
echo "Upstream GW     : ${UPSTREAM_GATEWAY:-n/a}"
echo "Override Target : $TARGET"
echo "Reflector TUN   : $IFACE"
if [ -x "$APP" ]; then
  VERSION="$($APP -version 2>/dev/null || true)"
  [ -n "$VERSION" ] && echo "Binary Version  : $VERSION"
fi
echo

echo "1. Core Reflector & Routing:"
echo "----------------------------"
if pid_ok "$REFLECTOR_PIDFILE"; then
  ok "Reflector process running (PID $(cat "$REFLECTOR_PIDFILE"))"
else
  fail "Reflector process is NOT running"
fi

if ip link show "$IFACE" >/dev/null 2>&1; then
  ok "TUN interface $IFACE is UP"
else
  fail "TUN interface $IFACE does NOT exist"
fi

if ip route get "$TARGET" 2>/dev/null | grep -q "$IFACE"; then
  ok "Routing $TARGET/32 -> $IFACE confirmed"
else
  fail "Routing $TARGET/32 does NOT point to $IFACE"
fi

if iptables -L "$REFLECT_CHAIN" -n >/dev/null 2>&1; then
  ok "Firewall bypass chain $REFLECT_CHAIN active"
else
  fail "Firewall bypass chain $REFLECT_CHAIN missing"
fi

echo
case "$TOPOLOGY_MODE" in
  main-router)
    echo "2. Mode 1: Main Router DHCP Route Injection:"
    echo "--------------------------------------------"
    command -v dnsmasq >/dev/null 2>&1 && ok "dnsmasq is available" || fail "dnsmasq missing"
    found=""
    for d in "$DNSMASQ_CONF_DIR" /tmp/dnsmasq.d /tmp/dnsmasq.*.d; do
      [ -n "$d" ] || continue
      f="$d/$DNSMASQ_SNIPPET_NAME"
      if [ -f "$f" ]; then found="$f"; break; fi
    done
    if [ -n "$found" ]; then
      ok "Targeted DHCP Option121 snippet active: $found"
      sed 's/^/     /' "$found"
    else
      fail "Targeted DHCP Option121 snippet not found"
    fi
    ;;
  wireless-repeater)
    echo "2. Mode 2: Wireless Repeater DHCP Injection:"
    echo "--------------------------------------------"
    if pid_ok "$DHCP_PIDFILE"; then
      ok "DHCP121 injector running (PID $(cat "$DHCP_PIDFILE"))"
    else
      fail "DHCP121 injector is NOT running"
    fi

    if [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ] && [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null)" = 1 ]; then
      ok "Bridge netfilter enabled (bridge-nf-call-iptables=1)"
    else
      fail "Bridge netfilter disabled/unavailable"
    fi

    if iptables -L "$DHCP_CHAIN" -n >/dev/null 2>&1; then
      ok "DHCP ACK interception chain $DHCP_CHAIN active"
    else
      fail "DHCP ACK interception chain $DHCP_CHAIN missing"
    fi

    # Extract learned physical Wi-Fi interface and last DHCP injection
    learned_if="$(grep 'learned iPhone ingress interface:' "$DHCP_LOG" 2>/dev/null | tail -1 | awk '{for(i=1;i<=NF;i++) if($i=="interface:") print $(i+1)}')"
    last_injected="$(grep 'INJECTED DHCP ACK' "$DHCP_LOG" 2>/dev/null | tail -1)"
    if [ -n "$learned_if" ]; then
      ok "iPhone Wi-Fi ingress port learned: $learned_if"
    else
      info "Waiting for iPhone DHCP Request to learn Wi-Fi port"
    fi

    if [ -n "$last_injected" ]; then
      ok "Latest DHCP ACK injection:"
      echo "     $last_injected"
    else
      warn "No DHCP ACK injected yet (toggle iPhone Wi-Fi OFF/ON once)"
    fi
    ;;
  *) fail "Unknown TOPOLOGY_MODE=$TOPOLOGY_MODE" ;;
esac

echo
echo "3. Live Traffic & Reflector Activity:"
echo "-------------------------------------"
last_rewrite="$(grep 'reflector rewrote packet #' "$LOG" 2>/dev/null | tail -1)"
if [ -n "$last_rewrite" ]; then
  pkt_num="$(echo "$last_rewrite" | awk -F'#' '{print $2}' | awk -F':' '{print $1}')"
  ok "Active: Total reflected packets: #$pkt_num"
  echo "     Latest: $last_rewrite"
else
  info "Idle: No SideStore traffic reflected yet (open SideStore and tap Refresh)"
fi

echo
echo "=================================================="
echo "Next step: Toggle iPhone Wi-Fi OFF/ON once, then open SideStore -> Refresh."
echo "=================================================="

