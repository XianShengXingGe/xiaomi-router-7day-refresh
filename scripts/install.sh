#!/bin/sh
# Xiaomi Router 7-Day Refresh installer - bilingual & simplified edition.

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

LANG_CHOICE=1 # 1: 中文, 2: English

msg() {
  if [ "$LANG_CHOICE" -eq 2 ]; then
    echo "$2"
  else
    echo "$1"
  fi
}

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
      y|Y|yes|YES|Yes|1) return 0 ;;
      n|N|no|NO|No|0) return 1 ;;
      *) msg "请输入 y 或 n。" "Please answer y or n." >&2 ;;
    esac
  done
}

normalize_mac() {
  raw="$1"
  clean="$(echo "$raw" | tr 'A-F' 'a-f' | tr -d ':-. ')"
  if [ "${#clean}" -eq 12 ]; then
    echo "$clean" | sed 's/\(..\)/\1:/g; s/:$//'
  else
    echo "$raw"
  fi
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
    *) die "$(msg "不支持的 CPU 架构: ${arch:-未知} (仅支持 arm64 / amd64)" "Unsupported CPU architecture: ${arch:-unknown} (supported: arm64, amd64)")" ;;
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

download_file() {
  url="$1"; out="$2"; rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    curl -fLk -o "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
  fi
  return 1
}

download_with_fallback() {
  url="$1"; out="$2"
  if download_file "$url" "$out"; then return 0; fi
  # Try China CDN/Proxy mirror if direct GitHub download fails
  mirror_url="https://ghproxy.net/$url"
  note "$(msg "尝试镜像源下载: $mirror_url" "Retrying with mirror: $mirror_url")"
  if download_file "$mirror_url" "$out"; then return 0; fi
  return 1
}

install_asset() {
  name="$1"; out="$2"; base="$3"
  if [ -s "$SCRIPT_DIR/$name" ]; then
    note "$(msg "使用本地内置组件: $name" "Using local asset: $name")"
    cp "$SCRIPT_DIR/$name" "$out" || return 1
  else
    note "$(msg "下载组件: $name" "Downloading: $name")"
    download_with_fallback "$base/$name" "$out" || return 1
  fi
}

require_common() {
  [ "$(id -u 2>/dev/null)" = "0" ] || die "$(msg "请在路由器上以 root 用户执行。" "Must run as root on the router.")"
  command -v ip >/dev/null 2>&1 || die "$(msg "缺少系统 ip 命令。" "Missing ip command.")"
  command -v iptables >/dev/null 2>&1 || die "$(msg "缺少系统 iptables 命令。" "Missing iptables command.")"
  [ -e /dev/net/tun ] || die "$(msg "缺少 /dev/net/tun 内核设备。" "Missing /dev/net/tun.")"
}

install_autostart() {
  [ -f "$RC_LOCAL" ] || { warn "$RC_LOCAL does not exist; skipping auto start."; return; }
  if grep -q "$START_SCRIPT" "$RC_LOCAL" 2>/dev/null; then
    note "$(msg "开机自启动已配置。" "Auto start already configured in $RC_LOCAL.")"
    return
  fi
  if grep -q '^exit 0' "$RC_LOCAL" 2>/dev/null; then
    sed -i "/^exit 0/i $START_SCRIPT \\&" "$RC_LOCAL"
  else
    printf '\n%s &\n' "$START_SCRIPT" >> "$RC_LOCAL"
  fi
  note "$(msg "已成功添加开机自启动至 $RC_LOCAL" "Auto start added to $RC_LOCAL")"
}

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
  echo "=================================================="
  echo " Xiaomi Router 7-Day Refresh Installer"
  echo " 小米/OpenWrt 路由器 SideStore 7天自动刷新安装引导"
  echo "=================================================="
  require_common

  # 语言选择 (Language selection)
  echo
  echo "Select language / 选择语言:"
  echo "  1) 中文 (Chinese) [默认 / Default]"
  echo "  2) English"
  lang_in="$(ask "选择语言 / Language" "1")"
  case "$lang_in" in
    2|en|EN|English|english) LANG_CHOICE=2 ;;
    *) LANG_CHOICE=1 ;;
  esac
  echo

  # 步骤 1：选择网络拓扑
  msg "【步骤 1/3】请选择网络拓扑模式:" "[Step 1/3] Choose deployment topology:"
  msg "  1) 主路由模式 (Main router)" "  1) Main router"
  msg "     iPhone 直接连接当前路由器，由本路由分配 IP 与默认网关" "     iPhone connects directly to this router; this router provides DHCP/gateway."
  msg "  2) 无线中继 / 子路由模式 (Wireless repeater / Child router) [推荐/默认]" "  2) Wireless repeater / child router [Recommended/Default]"
  msg "     当前路由作为中继/AP，由上级主路由分配 IP 与网关 (免改主路由，实测最稳定)" "     iPhone connects here, DHCP/gateway comes from upstream router."

  MODE_DEFAULT=2
  case "$OLD_TOPOLOGY" in
    main-router) MODE_DEFAULT=1 ;;
    wireless-repeater|relay-packet) MODE_DEFAULT=2 ;;
  esac

  choice="$(ask "$(msg "拓扑模式" "Topology")" "$MODE_DEFAULT")"
  case "$choice" in
    1|main|main-router) TOPOLOGY_MODE="main-router" ;;
    2|repeater|wireless-repeater|relay) TOPOLOGY_MODE="wireless-repeater" ;;
    *) die "$(msg "无效的拓扑选项: $choice" "Invalid topology: $choice")" ;;
  esac
  echo

  # 步骤 2：输入 iPhone Wi-Fi MAC 地址
  msg "【步骤 2/3】请输入 iPhone Wi-Fi MAC 地址:" "[Step 2/3] Enter iPhone Wi-Fi MAC address:"
  msg "提示: 在 iPhone [设置 -> 无线局域网 -> 当前Wi-Fi右侧(i)详情] 中查看 (私有无线局域网地址)" "Tip: View on iPhone in [Settings -> Wi-Fi -> (i) details] (Private Wi-Fi Address)"
  
  while :; do
    raw_mac="$(ask "$(msg "iPhone MAC 地址" "iPhone MAC")" "$OLD_MAC")"
    IPHONE_MAC="$(normalize_mac "$raw_mac")"
    if valid_mac "$IPHONE_MAC"; then
      break
    else
      msg "[错误] MAC 地址格式不正确 (示例: aa:bb:cc:dd:ee:ff)，请重新输入。" "[ERROR] Invalid MAC format (e.g. aa:bb:cc:dd:ee:ff), please re-enter." >&2
    fi
  done
  echo

  # 自动探测参数
  LANIF="${OLD_LANIF:-$LANIF_DEFAULT}"
  [ -d "/sys/class/net/$LANIF" ] || LANIF="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  [ -n "$LANIF" ] || LANIF="$LANIF_DEFAULT"

  DETECTED_ROUTER_IP="$(detect_lan_ip "$LANIF")"
  ROUTER_LAN_IP="${OLD_ROUTER_IP:-$DETECTED_ROUTER_IP}"
  [ -n "$ROUTER_LAN_IP" ] || ROUTER_LAN_IP="192.168.31.1"

  TARGET="$TARGET_DEFAULT"
  IFACE="${OLD_IFACE:-$IFACE_DEFAULT}"
  UPSTREAM_GATEWAY=""
  DNSMASQ_CONF_DIR=""

  if [ "$TOPOLOGY_MODE" = "main-router" ]; then
    command -v dnsmasq >/dev/null 2>&1 || die "$(msg "主路由模式需要 dnsmasq 服务。" "Main-router mode requires dnsmasq.")"
    DETECTED_DIR="$(detect_dnsmasq_confdir 2>/dev/null || true)"
    DNSMASQ_CONF_DIR="${OLD_DNSMASQ_DIR:-$DETECTED_DIR}"
    UPSTREAM_GATEWAY="$ROUTER_LAN_IP"
  else
    DETECTED_GW="$(detect_default_gateway)"
    UPSTREAM_GATEWAY="${OLD_UPSTREAM:-$DETECTED_GW}"
    [ -n "$UPSTREAM_GATEWAY" ] || UPSTREAM_GATEWAY="192.168.1.1"
  fi

  # 步骤 3：智能配置确认与高级模式
  msg "【步骤 3/3】配置摘要与一键安装:" "[Step 3/3] Configuration summary:"
  echo "--------------------------------------------------"
  msg "拓扑模式 (Topology)     : $TOPOLOGY_MODE" "Topology mode           : $TOPOLOGY_MODE"
  msg "iPhone MAC 地址         : $IPHONE_MAC" "iPhone MAC address      : $IPHONE_MAC"
  msg "本路由 LAN IP (Router)  : $ROUTER_LAN_IP" "Router LAN IP           : $ROUTER_LAN_IP"
  if [ "$TOPOLOGY_MODE" = "wireless-repeater" ]; then
    msg "上级主路由网关 (Gateway): $UPSTREAM_GATEWAY" "Upstream gateway        : $UPSTREAM_GATEWAY"
  fi
  msg "网桥接口 (LAN/Bridge)   : $LANIF" "LAN / Bridge interface  : $LANIF"
  msg "TUN 反射网卡 (TUN Dev)  : $IFACE (Target: $TARGET)" "TUN reflector device    : $IFACE (Target: $TARGET)"
  echo "--------------------------------------------------"
  msg "直接按 [回车] 立即快速安装并启动" "Press [Enter] to install with recommended defaults"
  msg "或输入 'e' 进入高级自定义微调配置" "or enter 'e' for advanced custom settings"
  
  confirm="$(ask "$(msg "确认安装 / Confirm [Enter/e]" "Confirm install [Enter/e]")" "")"
  
  if [ "$confirm" = "e" ] || [ "$confirm" = "E" ]; then
    echo
    msg "--- 高级自定义设置 ---" "--- Advanced Custom Settings ---"
    LANIF="$(ask "$(msg "局域网网桥接口" "LAN/bridge interface")" "$LANIF")"
    ROUTER_LAN_IP="$(ask "$(msg "当前路由器 LAN IP" "This router LAN IPv4")" "$ROUTER_LAN_IP")"
    valid_ipv4 "$ROUTER_LAN_IP" || die "$(msg "无效的 Router IP: $ROUTER_LAN_IP" "Invalid router LAN IP: $ROUTER_LAN_IP")"

    if [ "$TOPOLOGY_MODE" = "wireless-repeater" ]; then
      UPSTREAM_GATEWAY="$(ask "$(msg "上级主路由网关 IP" "Upstream default gateway IPv4")" "$UPSTREAM_GATEWAY")"
      valid_ipv4 "$UPSTREAM_GATEWAY" || die "$(msg "无效的网关 IP: $UPSTREAM_GATEWAY" "Invalid gateway: $UPSTREAM_GATEWAY")"
    else
      DNSMASQ_CONF_DIR="$(ask "$(msg "dnsmasq conf-dir 路径" "Active dnsmasq conf-dir")" "$DNSMASQ_CONF_DIR")"
    fi
    IFACE="$(ask "$(msg "TUN 网卡名称" "Reflector TUN interface name")" "$IFACE")"
  fi

  echo
  note "$(msg "开始安装组件..." "Installing components...")"

  arch="$(detect_arch)"
  asset="$APP_NAME-linux-$arch"
  if [ "$VERSION" = "latest" ]; then
    base="https://github.com/$REPO/releases/latest/download"
  else
    base="https://github.com/$REPO/releases/download/$VERSION"
  fi

  mkdir -p "$INSTALL_DIR" || die "$(msg "无法创建安装目录 $INSTALL_DIR" "Cannot create $INSTALL_DIR")"

  # 清理历史运行实例并备份旧配置
  if [ -x "$CLEANUP_SCRIPT" ]; then
    note "$(msg "正在清理旧版本运行时..." "Cleaning previous runtime...")"
    "$CLEANUP_SCRIPT" >/dev/null 2>&1 || true
  fi
  if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo old)" 2>/dev/null || true
  fi

  cat > "$CONFIG" <<EOF2
# Xiaomi Router 7-Day Refresh configuration
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

  install_asset "$asset" "$APP" "$base" || die "$(msg "安装二进制核心失败: $asset" "Failed to install $asset")"
  install_asset start.sh "$START_SCRIPT" "$base" || die "$(msg "安装 start.sh 失败" "Failed to install start.sh")"
  install_asset status.sh "$STATUS_SCRIPT" "$base" || die "$(msg "安装 status.sh 失败" "Failed to install status.sh")"
  install_asset cleanup.sh "$CLEANUP_SCRIPT" "$base" || die "$(msg "安装 cleanup.sh 失败" "Failed to install cleanup.sh")"
  install_asset diagnose.sh "$DIAG_SCRIPT" "$base" || die "$(msg "安装 diagnose.sh 失败" "Failed to install diagnose.sh")"
  chmod +x "$APP" "$START_SCRIPT" "$STATUS_SCRIPT" "$CLEANUP_SCRIPT" "$DIAG_SCRIPT" || die "chmod failed"

  install_autostart

  echo
  note "$(msg "正在启动服务..." "Starting service...")"
  START_DELAY=2 "$START_SCRIPT" || die "$(msg "启动服务失败" "Start service failed")"
  
  echo
  "$STATUS_SCRIPT"

  echo
  note "$(msg "安装完成！日常使用说明:" "Installation finished! Usage instructions:")"
  msg "1. 首次使用请在 iPhone 上 [关闭 Wi-Fi -> 等待2秒 -> 重新连接 Wi-Fi] 重新获取 DHCP 路由。" "1. On iPhone, toggle Wi-Fi OFF and ON once to receive the 10.7.0.1/32 DHCP route."
  msg "2. 打开 SideStore 点击 Refresh，即可完成 7 天免越狱签名刷新。" "2. Open SideStore and tap Refresh to refresh your apps."
  msg "3. 查看状态: $STATUS_SCRIPT" "3. Check status: $STATUS_SCRIPT"
  msg "4. 诊断排查: $DIAG_SCRIPT" "4. Diagnostics: $DIAG_SCRIPT"
  echo
}

main "$@"

