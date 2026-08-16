#!/bin/sh
# Xiaomi Router 7-Day Refresh installer - dual topology release.

set -u

REPO="${REPO:-XianShengXingGe/xiaomi-router-7day-refresh}"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/data}"
APP_NAME="${APP_NAME:-xiaomi-router-7day-refresh}"
APP="$INSTALL_DIR/$APP_NAME"
START_SCRIPT="$INSTALL_DIR/$APP_NAME-start.sh"
STATUS_SCRIPT="$INSTALL_DIR/$APP_NAME-status.sh"
CLEANUP_SCRIPT="$INSTALL_DIR/$APP_NAME-cleanup.sh"
DIAG_SCRIPT="$INSTALL_DIR/$APP_NAME-diagnose.sh"
CONFIG="$INSTALL_DIR/$APP_NAME.conf"
RC_LOCAL="/etc/rc.local"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"

TARGET_DEFAULT="10.7.0.1"
LANIF_DEFAULT="br-lan"
IFACE_DEFAULT="sidestore"

note() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

ask() {
  prompt="$1"; default="$2"
  printf "%s" "$prompt" >&2
  [ -n "$default" ] && printf " [%s]" "$default" >&2
  printf ": " >&2
  read -r answer
  [ -z "$answer" ] && answer="$default"
  printf "%s" "$answer"
}

ask_yes_no() {
  prompt="$1"; default="$2"
  while :; do
    answer="$(ask "$prompt" "$default")"
    case "$answer" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      *) echo "Please answer y or n." >&2 ;;
    esac
  done
}

valid_ipv4() {
  ip="$1"
  echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
  OLDIFS="$IFS"; IFS=.; set -- $ip; IFS="$OLDIFS"
  [ "$#" -eq 4 ] || return 1
  for part in "$@"; do
    [ "$part" -ge 0 ] 2>/dev/null && [ "$part" -le 255 ] 2>/dev/null || return 1
  done
}

valid_mac() { echo "$1" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; }

detect_arch() {
  arch="$(uname -m 2>/dev/null || true)"
  case "$arch" in
    aarch64|arm64) echo arm64 ;;
    x86_64|amd64) echo amd64 ;;
    *) die "Unsupported CPU architecture: ${arch:-unknown}. Supported: arm64, amd64." ;;
  esac
}

detect_lan_ip() {
  dev="$1"
  ip -4 addr show "$dev" 2>/dev/null | awk '/inet / {gsub(/\/.*/,"",$2); print $2; exit}'
}

detect_default_gateway() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

detect_dnsmasq_confdir() {
  for f in /var/etc/dnsmasq.conf.* /var/etc/dnsmasq.conf /tmp/dnsmasq.conf.* /tmp/dnsmasq.conf; do
    [ -f "$f" ] || continue
    d="$(sed -n 's/^conf-dir=\([^,]*\).*/\1/p' "$f" | head -1)"
    [ -n "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}

download() {
  url="$1"; out="$2"; rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    curl -fLk -o "$out" "$url" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url" || return 1
  else
    die "Neither curl nor wget is available. Use the offline release bundle."
  fi
  [ -s "$out" ]
}

install_asset() {
  name="$1"; out="$2"; base="$3"
  if [ -s "$SCRIPT_DIR/$name" ]; then
    note "Using local asset: $name"
    cp "$SCRIPT_DIR/$name" "$out" || return 1
  else
    note "Downloading: $name"
    download "$base/$name" "$out" || return 1
  fi
}

require_common() {
  [ "$(id -u 2>/dev/null)" = "0" ] || die "Run as root on the router."
  command -v ip >/dev/null 2>&1 || die "Missing ip command."
  command -v iptables >/dev/null 2>&1 || die "Missing iptables command."
  [ -e /dev/net/tun ] || die "Missing /dev/net/tun."
}

install_autostart() {
  [ -f "$RC_LOCAL" ] || { warn "$RC_LOCAL does not exist; skipping auto start."; return; }
  if grep -q "$START_SCRIPT" "$RC_LOCAL" 2>/dev/null; then
    note "Auto start already exists in $RC_LOCAL."
    return
  fi
  if grep -q '^exit 0' "$RC_LOCAL" 2>/dev/null; then
    sed -i "/^exit 0/i $START_SCRIPT \&" "$RC_LOCAL"
  else
    printf '\n%s &\n' "$START_SCRIPT" >> "$RC_LOCAL"
  fi
  note "Auto start added to $RC_LOCAL."
}

# Load prior values only as prompt defaults.
OLD_TOPOLOGY=""
OLD_MAC=""
OLD_LANIF=""
OLD_IFACE=""
OLD_ROUTER_IP=""
OLD_UPSTREAM=""
OLD_DNSMASQ_DIR=""
if [ -f "$CONFIG" ]; then
  . "$CONFIG"
  OLD_TOPOLOGY="${TOPOLOGY_MODE:-${NETWORK_MODE:-}}"
  OLD_MAC="${IPHONE_MAC:-}"
  OLD_LANIF="${LANIF:-}"
  OLD_IFACE="${IFACE:-}"
  OLD_ROUTER_IP="${ROUTER_LAN_IP:-}"
  OLD_UPSTREAM="${UPSTREAM_GATEWAY:-}"
  OLD_DNSMASQ_DIR="${DNSMASQ_CONF_DIR:-}"
fi

main() {
  echo "Xiaomi Router 7-Day Refresh"
  echo "Dual topology installer - SideStore Override Peer 10.7.0.1"
  echo
  require_common

  echo "Choose deployment topology:"
  echo "  1) Main router"
  echo "     iPhone connects directly to this router; this router provides DHCP/default gateway."
  echo "  2) Wireless repeater / child router"
  echo "     iPhone connects to this router, but DHCP/default gateway comes from an upstream router."
  MODE_DEFAULT=1
  case "$OLD_TOPOLOGY" in wireless-repeater|relay-packet) MODE_DEFAULT=2 ;; esac
  choice="$(ask "Topology" "$MODE_DEFAULT")"
  case "$choice" in
    1|main|main-router) TOPOLOGY_MODE="main-router" ;;
    2|repeater|wireless-repeater|relay) TOPOLOGY_MODE="wireless-repeater" ;;
    *) die "Invalid topology: $choice" ;;
  esac

  LANIF="$(ask "LAN/bridge interface" "${OLD_LANIF:-$LANIF_DEFAULT}")"
  [ -d "/sys/class/net/$LANIF" ] || die "Interface $LANIF does not exist."

  DETECTED_ROUTER_IP="$(detect_lan_ip "$LANIF")"
  ROUTER_LAN_IP="$(ask "This router LAN IPv4" "${OLD_ROUTER_IP:-$DETECTED_ROUTER_IP}")"
  valid_ipv4 "$ROUTER_LAN_IP" || die "Invalid router LAN IPv4: $ROUTER_LAN_IP"

  IPHONE_MAC="$(ask "iPhone Wi-Fi MAC (Private Wi-Fi Address for this SSID)" "$OLD_MAC")"
  valid_mac "$IPHONE_MAC" || die "Invalid iPhone MAC: $IPHONE_MAC"
  IPHONE_MAC="$(echo "$IPHONE_MAC" | tr 'A-F' 'a-f')"

  IFACE="$(ask "Reflector TUN interface name" "${OLD_IFACE:-$IFACE_DEFAULT}")"
  TARGET="$TARGET_DEFAULT"
  note "SideStore override target fixed to $TARGET (validated end-to-end)."
  UPSTREAM_GATEWAY=""
  DNSMASQ_CONF_DIR=""

  if [ "$TOPOLOGY_MODE" = "main-router" ]; then
    command -v dnsmasq >/dev/null 2>&1 || die "Main-router mode requires dnsmasq."
    [ -x /etc/init.d/dnsmasq ] || warn "/etc/init.d/dnsmasq not found; start.sh will try service dnsmasq restart."
    DETECTED_DIR="$(detect_dnsmasq_confdir 2>/dev/null || true)"
    DNSMASQ_CONF_DIR="$(ask "Active dnsmasq conf-dir" "${OLD_DNSMASQ_DIR:-$DETECTED_DIR}")"
    [ -n "$DNSMASQ_CONF_DIR" ] || die "Could not detect dnsmasq conf-dir. Check /var/etc/dnsmasq.conf.* for a conf-dir= line."
    UPSTREAM_GATEWAY="$ROUTER_LAN_IP"
  else
    [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ] || die "Repeater mode requires bridge netfilter."
    iptables -m physdev -h >/dev/null 2>&1 || die "Repeater mode requires iptables physdev match."
    iptables -m string -h >/dev/null 2>&1 || die "Repeater mode requires iptables string match."
    DETECTED_GW="$(detect_default_gateway)"
    UPSTREAM_GATEWAY="$(ask "Upstream/default gateway IPv4" "${OLD_UPSTREAM:-$DETECTED_GW}")"
    valid_ipv4 "$UPSTREAM_GATEWAY" || die "Invalid upstream gateway: $UPSTREAM_GATEWAY"
  fi

  arch="$(detect_arch)"
  asset="$APP_NAME-linux-$arch"
  if [ "$VERSION" = "latest" ]; then
    base="https://github.com/$REPO/releases/latest/download"
  else
    base="https://github.com/$REPO/releases/download/$VERSION"
  fi

  mkdir -p "$INSTALL_DIR" || die "Cannot create $INSTALL_DIR"

  # Clean the previously installed generation before replacing its config.
  if [ -x "$CLEANUP_SCRIPT" ]; then
    note "Cleaning previous installation runtime..."
    "$CLEANUP_SCRIPT" >/dev/null 2>&1 || true
  fi
  if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo old)" 2>/dev/null || true
  fi

  cat > "$CONFIG" <<EOF2
# Xiaomi Router 7-Day Refresh 0.5.x configuration
TOPOLOGY_MODE="$TOPOLOGY_MODE"
IPHONE_MAC="$IPHONE_MAC"
LANIF="$LANIF"
ROUTER_LAN_IP="$ROUTER_LAN_IP"
UPSTREAM_GATEWAY="$UPSTREAM_GATEWAY"
DNSMASQ_CONF_DIR="$DNSMASQ_CONF_DIR"
IFACE="$IFACE"
TARGET="$TARGET"
APP="$APP"
LOG="/tmp/$APP_NAME.log"
DHCP_LOG="/tmp/$APP_NAME-dhcp.log"
EOF2

  install_asset "$asset" "$APP" "$base" || die "Failed to install $asset"
  install_asset start.sh "$START_SCRIPT" "$base" || die "Failed to install start.sh"
  install_asset status.sh "$STATUS_SCRIPT" "$base" || die "Failed to install status.sh"
  install_asset cleanup.sh "$CLEANUP_SCRIPT" "$base" || die "Failed to install cleanup.sh"
  install_asset diagnose.sh "$DIAG_SCRIPT" "$base" || die "Failed to install diagnose.sh"
  chmod +x "$APP" "$START_SCRIPT" "$STATUS_SCRIPT" "$CLEANUP_SCRIPT" "$DIAG_SCRIPT" || die "chmod failed"

  if ask_yes_no "Set auto start on router boot?" y; then
    install_autostart
  fi

  if ask_yes_no "Start now?" y; then
    START_DELAY=2 "$START_SCRIPT" || die "Start failed"
    echo
    "$STATUS_SCRIPT"
  else
    note "Start skipped. Run: START_DELAY=2 $START_SCRIPT"
  fi

  echo
  note "Install finished."
  echo "Topology : $TOPOLOGY_MODE"
  echo "Target   : $TARGET"
  echo "iPhone   : $IPHONE_MAC"
  echo "Status   : $STATUS_SCRIPT"
  echo "Diagnose : $DIAG_SCRIPT"
  echo
  warn "After the first install/reboot, toggle iPhone Wi-Fi OFF/ON once so DHCP can install the $TARGET/32 host route."
}

main "$@"
