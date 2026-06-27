#!/bin/sh
# Interactive installer for Xiaomi Router Auto-Sign.
# Run this script on the router after logging in through SSH.

set -u

REPO="${REPO:-XianShengXingGe/xiaomi-router-autosign}"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/data}"
APP_NAME="${APP_NAME:-xiaomi-router-autosign}"
APP="$INSTALL_DIR/$APP_NAME"
START_SCRIPT="$INSTALL_DIR/$APP_NAME-start.sh"
STATUS_SCRIPT="$INSTALL_DIR/$APP_NAME-status.sh"
CLEANUP_SCRIPT="$INSTALL_DIR/$APP_NAME-cleanup.sh"
CONFIG="$INSTALL_DIR/$APP_NAME.conf"
RC_LOCAL="/etc/rc.local"
TARGET_DEFAULT="10.7.0.1"
IFACE_DEFAULT="sidestore"
LANIF_DEFAULT="br-lan"

die() {
  echo
  echo "[ERROR] $*" >&2
  exit 1
}

note() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*"
}

ask() {
  prompt="$1"
  default="$2"
  printf "%s" "$prompt" >&2
  if [ -n "$default" ]; then
    printf " [%s]" "$default" >&2
  fi
  printf ": " >&2
  read -r answer
  if [ -z "$answer" ]; then
    answer="$default"
  fi
  printf "%s" "$answer"
}

ask_yes_no() {
  prompt="$1"
  default="$2"
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
  OLD_IFS="$IFS"
  IFS=.
  set -- $ip
  IFS="$OLD_IFS"
  [ "$#" -eq 4 ] || return 1
  for part in "$@"; do
    [ "$part" -ge 0 ] 2>/dev/null && [ "$part" -le 255 ] 2>/dev/null || return 1
  done
  return 0
}

detect_arch() {
  arch="$(uname -m 2>/dev/null || true)"
  case "$arch" in
    aarch64|arm64) echo "arm64" ;;
    x86_64|amd64) echo "amd64" ;;
    *) die "Unsupported CPU architecture: ${arch:-unknown}. This installer supports arm64 and amd64 release binaries." ;;
  esac
}

download() {
  url="$1"
  out="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url" || return 1
  elif command -v curl >/dev/null 2>&1; then
    curl -L -o "$out" "$url" || return 1
  else
    die "Neither wget nor curl is available on this router."
  fi
}

require_router_shell() {
  [ "$(id -u 2>/dev/null)" = "0" ] || die "Please run this installer as root on the router."
  [ -e /dev/net/tun ] || die "Missing /dev/net/tun. This router firmware may not support TUN."
  command -v ip >/dev/null 2>&1 || die "Missing ip command."
  command -v iptables >/dev/null 2>&1 || die "Missing iptables command."
  if [ ! -f /etc/openwrt_release ] && [ ! -d /etc/config ]; then
    warn "This does not look like a typical OpenWrt shell."
    warn "The installer must be run on the router via SSH, not on Windows or macOS."
    ask_yes_no "Continue anyway?" "n" || exit 1
  fi
}

install_autostart() {
  [ -f "$RC_LOCAL" ] || {
    warn "$RC_LOCAL does not exist. Skipping auto start setup."
    return
  }
  if grep -q "$START_SCRIPT" "$RC_LOCAL" 2>/dev/null; then
    note "Auto start already exists in $RC_LOCAL."
    return
  fi
  if grep -q '^exit 0' "$RC_LOCAL" 2>/dev/null; then
    sed -i "/^exit 0/i $START_SCRIPT &" "$RC_LOCAL"
  else
    printf "\n%s &\n" "$START_SCRIPT" >> "$RC_LOCAL"
  fi
  note "Auto start added to $RC_LOCAL."
}

show_reminders() {
  cat <<'EOF'

Before using SideStore / LiveContainer automation:

1. On the iPhone, open the current Wi-Fi network settings and set
   "Private Wi-Fi Address" to "Fixed" or "Off".
2. In the Xiaomi router admin page, enable and use DHCP static IP assignment
   to bind this iPhone to the same LAN IP you entered here.
3. In iOS Shortcuts, create an automation for joining this Wi-Fi, then trigger
   your SideStore / LiveContainer refresh flow.

EOF
}

main() {
  echo "Xiaomi Router Auto-Sign installer"
  echo
  echo "Run this after SSH login to your router."
  echo "Example only: ssh root@192.168.31.1"
  echo "Your router address may be different."
  echo

  require_router_shell
  show_reminders

  while :; do
    IPHONE="$(ask "Enter the iPhone fixed LAN IP" "")"
    valid_ipv4 "$IPHONE" && break
    echo "Invalid IPv4 address. Example: 192.168.31.100"
  done

  LANIF="$(ask "Enter LAN interface name" "$LANIF_DEFAULT")"
  IFACE="$(ask "Enter TUN interface name" "$IFACE_DEFAULT")"
  TARGET="$(ask "Enter SideStore / LiveContainer target IP" "$TARGET_DEFAULT")"
  valid_ipv4 "$TARGET" || die "Invalid target IP: $TARGET"

  arch="$(detect_arch)"
  asset="$APP_NAME-linux-$arch"
  if [ "$VERSION" = "latest" ]; then
    base_url="https://github.com/$REPO/releases/latest/download"
  else
    base_url="https://github.com/$REPO/releases/download/$VERSION"
  fi

  note "CPU architecture: $arch"
  note "Installing to $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR" || die "Cannot create $INSTALL_DIR"

  cat > "$CONFIG" <<EOF
IPHONE="$IPHONE"
LANIF="$LANIF"
IFACE="$IFACE"
TARGET="$TARGET"
APP="$APP"
LOG="/tmp/$APP_NAME.log"
EOF

  note "Config written to $CONFIG"

  note "Downloading $asset"
  download "$base_url/$asset" "$APP" || die "Failed to download $base_url/$asset"
  chmod +x "$APP" || die "Cannot chmod $APP"

  script_base="$base_url"
  note "Downloading helper scripts"
  download "$script_base/start.sh" "$START_SCRIPT" || die "Failed to download start.sh"
  download "$script_base/status.sh" "$STATUS_SCRIPT" || die "Failed to download status.sh"
  download "$script_base/cleanup.sh" "$CLEANUP_SCRIPT" || die "Failed to download cleanup.sh"
  chmod +x "$START_SCRIPT" "$STATUS_SCRIPT" "$CLEANUP_SCRIPT" || die "Cannot chmod helper scripts"

  if ask_yes_no "Set auto start on router boot?" "y"; then
    install_autostart
  else
    note "Auto start skipped."
  fi

  if ask_yes_no "Start now?" "y"; then
    "$START_SCRIPT"
    echo
    "$STATUS_SCRIPT"
  else
    note "Start skipped. You can run: $START_SCRIPT"
  fi

  echo
  note "Install finished."
  note "Status command: $STATUS_SCRIPT"
  note "Cleanup command: $CLEANUP_SCRIPT"
}

main "$@"
