# Changelog

## 0.5.2-public

- Added a self-updating `upgrade.sh` that downloads the latest GitHub `install.sh` before running it.
- Documented direct SSH installation and upgrade commands using curl.
- Bumped the helper version reported by the binary to `0.5.2-public`.

## 0.5.1-public

- Prepared a desensitized GitHub-ready release.
- Replaced environment-specific IP/MAC values in tests with RFC 5737 and synthetic fixtures.
- Fixed `upgrade.sh` to run `install.sh` via `sh`, avoiding executable-bit issues after Windows/SFTP transfers.
- Expanded `.gitignore` to exclude runtime configs, backups, logs, PID files, and local debug artifacts.
- Added `PUBLIC_RELEASE_NOTES.md` and `CODEX_GITHUB_HANDOFF.md`.

## 0.5.0-override-peer

- Switched the validated SideStore target from the auto-discovered Local VPN peer to the explicit Override Peer `10.7.0.1`.
- Kept both supported topologies: `main-router` and `wireless-repeater`.
- Mode 1 now installs `10.7.0.1/32 -> main router` through targeted dnsmasq Option 121.
- Mode 2 now injects `10.7.0.1/32 -> child router` into the upstream DHCP ACK while preserving the upstream default gateway.
- Unified both modes on the same TUN reflector targeting `10.7.0.1`.
- Added migration cleanup for legacy v0.4 `198.19.0.2` route/NAT/mangle state.
- Clarified that `START_DELAY=2` only shortens the startup wait; successful refresh depends on the service starting with `TARGET=10.7.0.1`.
- Wireless-repeater mode was validated end-to-end with a successful SideStore Refresh.

## 0.4.0-dual-topology

- Added two explicit deployment modes: `main-router` and `wireless-repeater`.
- Used `198.19.0.2` as an experimental Local VPN peer target.
- Added DHCP Option 121 host-route injection.
- Added AF_PACKET DHCP ACK patching for wireless-repeater mode.
