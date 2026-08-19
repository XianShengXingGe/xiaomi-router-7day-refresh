#!/bin/sh
# Download and run the latest GitHub installer to upgrade/reconfigure the router.

set -u

REPO="${REPO:-XianShengXingGe/xiaomi-router-7day-refresh}"
INSTALLER="/tmp/xiaomi-router-7day-refresh-install.$$"

die() { echo "[ERROR] $*" >&2; exit 1; }

download_file() {
  url="$1"; out="$2"; rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    curl -fLk --connect-timeout 4 -m 30 -o "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 5 -t 1 -O "$out" "$url" 2>/dev/null && [ -s "$out" ] && return 0
  fi
  return 1
}

download_with_fallback() {
  url="$1"; out="$2"
  # Try fast domestic mirror nodes first for Mainland China users
  for mirror in "https://ghfast.top" "https://gh.ddlc.top" "https://ghproxy.net"; do
    mirror_url="$mirror/$url"
    echo "[INFO] Trying mirror / 尝试镜像源: $mirror"
    if download_file "$mirror_url" "$out"; then return 0; fi
  done

  # Fallback to jsDelivr CDN for install script
  jsdelivr_url="https://cdn.jsdelivr.net/gh/$REPO@main/scripts/install.sh"
  echo "[INFO] Trying jsDelivr CDN: $jsdelivr_url"
  if download_file "$jsdelivr_url" "$out"; then return 0; fi

  # Direct GitHub official fallback
  echo "[INFO] Trying direct GitHub / 尝试直连 GitHub: $url"
  if download_file "$url" "$out"; then return 0; fi
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

