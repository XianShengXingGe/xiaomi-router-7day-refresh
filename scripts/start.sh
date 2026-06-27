#!/bin/sh
# Router-side 7-day refresh helper for SideStore / LiveContainer on OpenWrt/ShellClash.

CONFIG="${CONFIG:-/data/xiaomi-router-7day-refresh.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

IPHONE="${IPHONE:-}"
LANIF="${LANIF:-br-lan}"
IFACE="${IFACE:-sidestore}"
APP="${APP:-/data/xiaomi-router-7day-refresh}"
LOG="${LOG:-/tmp/xiaomi-router-7day-refresh.log}"
TARGET="${TARGET:-10.7.0.1}"

if [ -z "$IPHONE" ]; then
  echo "IPHONE is not configured. Edit $CONFIG or rerun the installer." >&2
  exit 1
fi

# Wait for LAN, firewall, and ShellClash rules to initialize.
sleep 60

for PID in $(ps | grep '[x]iaomi-router-7day-refresh' | awk '{print $1}'); do
  kill -9 "$PID" 2>/dev/null
done
sleep 1

ip route del "$TARGET/32" dev "$IFACE" 2>/dev/null
ip link del "$IFACE" 2>/dev/null

while iptables -D FORWARD -i "$LANIF" -o "$IFACE" -s "$IPHONE" -d "$TARGET" -j ACCEPT 2>/dev/null; do :; done
while iptables -D FORWARD -i "$IFACE" -o "$LANIF" -s "$TARGET" -d "$IPHONE" -j ACCEPT 2>/dev/null; do :; done
while iptables -t nat -D PREROUTING -i "$LANIF" -d "$TARGET" -j RETURN 2>/dev/null; do :; done

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf."$LANIF".rp_filter=0 >/dev/null 2>&1

rm -f "$LOG"
"$APP" -iface "$IFACE" -target "$TARGET" > "$LOG" 2>&1 &
echo $! > /tmp/xiaomi-router-7day-refresh.pid
sleep 3

ip link set "$IFACE" up
ip route replace "$TARGET/32" dev "$IFACE"
ip route flush cache

iptables -I FORWARD 1 -i "$LANIF" -o "$IFACE" -s "$IPHONE" -d "$TARGET" -j ACCEPT
iptables -I FORWARD 1 -i "$IFACE" -o "$LANIF" -s "$TARGET" -d "$IPHONE" -j ACCEPT
iptables -t nat -I PREROUTING 1 -i "$LANIF" -d "$TARGET" -j RETURN
