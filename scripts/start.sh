#!/bin/sh
# Start Xiaomi Router 7-Day Refresh - dual topology release.

CONFIG="${CONFIG:-/data/xiaomi-router-7day-refresh.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

APP_NAME="${APP_NAME:-xiaomi-router-7day-refresh}"
TOPOLOGY_MODE="${TOPOLOGY_MODE:-main-router}"
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
START_DELAY="${START_DELAY:-60}"
LEGACY_TARGET="198.19.0.2"

note() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

valid_ipv4() { echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }
valid_mac() { echo "$1" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; }

detect_lan_ip() {
  ip -4 addr show "$1" 2>/dev/null | awk '/inet / {gsub(/\/.*/,"",$2); print $2; exit}'
}

detect_dnsmasq_confdir() {
  for f in /var/etc/dnsmasq.conf.* /var/etc/dnsmasq.conf /tmp/dnsmasq.conf.* /tmp/dnsmasq.conf; do
    [ -f "$f" ] || continue
    d="$(sed -n 's/^conf-dir=\([^,]*\).*/\1/p' "$f" | head -1)"
    [ -n "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}

restart_dnsmasq() {
  if [ -x /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart
  elif command -v service >/dev/null 2>&1; then
    service dnsmasq restart
  else
    die "Cannot restart dnsmasq"
  fi
}

kill_pidfile() {
  pf="$1"
  [ -f "$pf" ] || return 0
  pid="$(cat "$pf" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    n=0
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 5 ]; do sleep 1; n=$((n+1)); done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pf"
}

remove_chain() {
  chain="$1"
  while iptables -D FORWARD -j "$chain" 2>/dev/null; do :; done
  iptables -F "$chain" 2>/dev/null || true
  iptables -X "$chain" 2>/dev/null || true
}

remove_old_runtime() {
  remove_chain "$DHCP_CHAIN"
  remove_chain "$REFLECT_CHAIN"
  for t in "$TARGET" "$LEGACY_TARGET"; do
    while iptables -t nat -D PREROUTING -i "$LANIF" -d "$t" -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING -i "$LANIF" -d "$t" -j ACCEPT 2>/dev/null; do :; done
    ip route del "$t/32" dev "$IFACE" 2>/dev/null || true
  done
  kill_pidfile "$DHCP_PIDFILE"
  kill_pidfile "$REFLECTOR_PIDFILE"
  ip link del "$IFACE" 2>/dev/null || true
}

wait_pid() {
  pid="$1"; log="$2"; label="$3"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    tail -40 "$log" 2>/dev/null || true
    die "$label exited during startup"
  fi
}

start_reflector() {
  rm -f "$LOG"
  "$APP" -mode reflector -iface "$IFACE" -target "$TARGET" >"$LOG" 2>&1 &
  pid=$!
  echo "$pid" > "$REFLECTOR_PIDFILE"
  wait_pid "$pid" "$LOG" reflector

  n=0
  while ! ip link show "$IFACE" >/dev/null 2>&1 && [ "$n" -lt 10 ]; do sleep 1; n=$((n+1)); done
  ip link show "$IFACE" >/dev/null 2>&1 || die "TUN interface $IFACE was not created"

  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf."$LANIF".rp_filter=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv4.conf."$IFACE".rp_filter=0 >/dev/null 2>&1 || true
  ip link set "$IFACE" up
  ip route replace "$TARGET/32" dev "$IFACE"
  ip route flush cache 2>/dev/null || true

  # Narrow SideStore reflection path bypass
  iptables -N "$REFLECT_CHAIN" 2>/dev/null || true
  iptables -F "$REFLECT_CHAIN"
  iptables -A "$REFLECT_CHAIN" -i "$LANIF" -o "$IFACE" -d "$TARGET" -j ACCEPT
  iptables -A "$REFLECT_CHAIN" -i "$IFACE" -o "$LANIF" -s "$TARGET" -j ACCEPT
  iptables -I FORWARD 1 -j "$REFLECT_CHAIN"
  iptables -t nat -I PREROUTING 1 -i "$LANIF" -d "$TARGET" -j RETURN 2>/dev/null || true
  iptables -t mangle -I PREROUTING 1 -i "$LANIF" -d "$TARGET" -j ACCEPT 2>/dev/null || true

  note "reflector ready: $TARGET/32 -> $IFACE"
}

start_main_router() {
  command -v dnsmasq >/dev/null 2>&1 || die "main-router mode requires dnsmasq"
  [ -n "$ROUTER_LAN_IP" ] || ROUTER_LAN_IP="$(detect_lan_ip "$LANIF")"
  valid_ipv4 "$ROUTER_LAN_IP" || die "invalid ROUTER_LAN_IP=$ROUTER_LAN_IP"

  if [ -z "$DNSMASQ_CONF_DIR" ] || [ ! -d "$DNSMASQ_CONF_DIR" ]; then
    DNSMASQ_CONF_DIR="$(detect_dnsmasq_confdir 2>/dev/null || true)"
  fi
  [ -n "$DNSMASQ_CONF_DIR" ] || die "could not detect active dnsmasq conf-dir"
  mkdir -p "$DNSMASQ_CONF_DIR" || die "cannot create dnsmasq conf-dir $DNSMASQ_CONF_DIR"

  snippet="$DNSMASQ_CONF_DIR/$DNSMASQ_SNIPPET_NAME"
  if dnsmasq --help 2>&1 | grep -q 'dhcp-mac'; then
    tag_line="dhcp-mac=set:xrr_sidestore,$IPHONE_MAC"
  else
    tag_line="dhcp-host=$IPHONE_MAC,set:xrr_sidestore"
  fi
  cat > "$snippet" <<EOF2
# Managed by xiaomi-router-7day-refresh. Do not edit while service is active.
$tag_line
dhcp-option=tag:xrr_sidestore,121,$TARGET/32,$ROUTER_LAN_IP,0.0.0.0/0,$ROUTER_LAN_IP
EOF2
  note "installed targeted dnsmasq Option121 config: $snippet"
  restart_dnsmasq || die "dnsmasq restart failed"
  sleep 1
  pidof dnsmasq >/dev/null 2>&1 || die "dnsmasq did not come back after restart"
  note "main-router DHCP route injection enabled for $IPHONE_MAC"
}

start_wireless_repeater() {
  valid_ipv4 "$ROUTER_LAN_IP" || die "invalid ROUTER_LAN_IP=$ROUTER_LAN_IP"
  valid_ipv4 "$UPSTREAM_GATEWAY" || die "invalid UPSTREAM_GATEWAY=$UPSTREAM_GATEWAY"
  [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ] || die "bridge netfilter unavailable"
  echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || die "cannot enable bridge-nf-call-iptables"
  iptables -m physdev -h >/dev/null 2>&1 || die "iptables physdev match unavailable"
  iptables -m string -h >/dev/null 2>&1 || die "iptables string match unavailable"

  # Clean stale dnsmasq snippets if switching topology
  removed=0
  for d in "$DNSMASQ_CONF_DIR" /tmp/dnsmasq.d /tmp/dnsmasq.*.d; do
    [ -n "$d" ] || continue
    f="$d/$DNSMASQ_SNIPPET_NAME"
    if [ -f "$f" ]; then rm -f "$f" && removed=1; fi
  done
  [ "$removed" -eq 0 ] || restart_dnsmasq || true

  rm -f "$DHCP_LOG"
  "$APP" -mode dhcp121-injector -phone-mac "$IPHONE_MAC" -target "$TARGET" \
    -router "$ROUTER_LAN_IP" -gateway "$UPSTREAM_GATEWAY" -bridge "$LANIF" >"$DHCP_LOG" 2>&1 &
  pid=$!
  echo "$pid" > "$DHCP_PIDFILE"
  wait_pid "$pid" "$DHCP_LOG" "DHCP121 injector"

  # Drop only the original ACK for this iPhone
  hexmac="$(echo "$IPHONE_MAC" | tr -d ':-' | tr 'A-F' 'a-f')"
  iptables -N "$DHCP_CHAIN" 2>/dev/null || true
  iptables -F "$DHCP_CHAIN"
  iptables -A "$DHCP_CHAIN" -p udp --sport 67 --dport 68 \
    -m physdev --physdev-is-bridged \
    -m string --algo bm --hex-string "|$hexmac|" \
    -m string --algo bm --hex-string '|63825363|' \
    -m string --algo bm --hex-string '|350105|' \
    -j DROP
  iptables -I FORWARD 1 -j "$DHCP_CHAIN"
  note "wireless-repeater DHCP ACK patcher ready for $IPHONE_MAC"
}

[ -x "$APP" ] || die "helper binary not found or not executable: $APP"
command -v ip >/dev/null 2>&1 || die "ip command is required"
command -v iptables >/dev/null 2>&1 || die "iptables is required"
[ -e /dev/net/tun ] || die "/dev/net/tun is required"
valid_mac "$IPHONE_MAC" || die "invalid or missing IPHONE_MAC in $CONFIG"

if [ "$START_DELAY" -gt 0 ] 2>/dev/null; then
  note "Waiting $START_DELAY seconds for network stabilization before starting..."
  sleep "$START_DELAY"
fi

remove_old_runtime
start_reflector

case "$TOPOLOGY_MODE" in
  main-router) start_main_router ;;
  wireless-repeater) start_wireless_repeater ;;
  *) die "Unknown TOPOLOGY_MODE=$TOPOLOGY_MODE (expected main-router or wireless-repeater)" ;;
esac

note "service started in $TOPOLOGY_MODE mode"
warn "If this is the first start or the iPhone renewed Wi-Fi settings, toggle iPhone Wi-Fi OFF/ON once to receive the $TARGET/32 DHCP route."

