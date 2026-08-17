#!/bin/sh
# Download and run the latest GitHub installer to upgrade/reconfigure the router.

set -u

REPO="${REPO:-XianShengXingGe/xiaomi-router-7day-refresh}"
VERSION="${VERSION:-latest}"
APP_NAME="${APP_NAME:-xiaomi-router-7day-refresh}"
CONFIG="${CONFIG:-/data/$APP_NAME.conf}"
INSTALLER="/tmp/$APP_NAME-install.$$"

die() { echo "[ERROR] $*" >&2; exit 1; }

download() {
  url="$1"
  out="$2"
  rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    curl -fLk -o "$out" "$url" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url" || return 1
  else
    die "Neither curl nor wget is available on this router."
  fi
  [ -s "$out" ] || return 1
}

cleanup() { rm -f "$INSTALLER"; }
trap cleanup 0

if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

echo "[INFO] Downloading GitHub installer: $BASE/install.sh"
download "$BASE/install.sh" "$INSTALLER" || die "Failed to download the GitHub installer."

if [ -f "$CONFIG" ]; then
  BACKUP="$CONFIG.pre-upgrade.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
  cp "$CONFIG" "$BACKUP" || die "Could not back up existing config to $BACKUP"
  echo "[OK] existing config backed up: $BACKUP"
fi

echo "[INFO] Starting interactive upgrade to SideStore Override Peer 10.7.0.1."
echo "[INFO] The downloaded installer will ask for the current router topology."
sh "$INSTALLER" "$@"
status=$?
exit "$status"
