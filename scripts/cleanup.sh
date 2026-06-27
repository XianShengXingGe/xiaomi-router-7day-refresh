#!/bin/sh
# Remove routes/rules/processes created by start.sh.

CONFIG="${CONFIG:-/data/xiaomi-router-autosign.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

IPHONE="${IPHONE:-}"
LANIF="${LANIF:-br-lan}"
IFACE="${IFACE:-sidestore}"
TARGET="${TARGET:-10.7.0.1}"

for PID in $(ps | grep '[x]iaomi-router-autosign' | awk '{print $1}'); do
  kill -9 "$PID" 2>/dev/null
done
for PID in $(ps | grep '[s]idestore-vpn-go' | awk '{print $1}'); do
  kill -9 "$PID" 2>/dev/null
done

ip route del "$TARGET/32" dev "$IFACE" 2>/dev/null
ip link del "$IFACE" 2>/dev/null

if [ -n "$IPHONE" ]; then
  while iptables -D FORWARD -i "$LANIF" -o "$IFACE" -s "$IPHONE" -d "$TARGET" -j ACCEPT 2>/dev/null; do :; done
  while iptables -D FORWARD -i "$IFACE" -o "$LANIF" -s "$TARGET" -d "$IPHONE" -j ACCEPT 2>/dev/null; do :; done
fi
while iptables -t nat -D PREROUTING -i "$LANIF" -d "$TARGET" -j RETURN 2>/dev/null; do :; done
