#!/bin/sh
# Download and run the latest GitHub installer to upgrade/reconfigure the router.

set -u

REPO="${REPO:-XianShengXingGe/xiaomi-router-7day-refresh}"
INSTALLER="/tmp/xiaomi-router-7day-refresh-install.$$"

die() { echo "[ERROR] $*" >&2; exit 1; }

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
  echo "[INFO] Retrying download with mirror / 尝试使用镜像源: $mirror_url"
  if download_file "$mirror_url" "$out"; then return 0; fi
  return 1
}

cleanup() { rm -f "$INSTALLER"; }
trap cleanup 0

BASE="https://github.com/$REPO/releases/latest/download"

echo "[INFO] Downloading installer: $BASE/install.sh"
download_with_fallback "$BASE/install.sh" "$INSTALLER" || die "Failed to download installer from GitHub or mirror."

echo "[INFO] Starting interactive upgrade/installation..."
sh "$INSTALLER" "$@"
status=$?
exit "$status"

