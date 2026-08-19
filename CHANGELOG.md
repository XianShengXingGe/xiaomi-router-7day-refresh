# Changelog

## 1.0.0

- 🎉 **Official 1.0 Milestone Release**: Full-featured, production-ready release for dual-topology SideStore 7-day refresh.
- **Extreme Performance & Zero-Alloc**: Rewrote transport checksum calculations with RFC 1071 associative properties, implemented fast pre-filtering for `AF_PACKET`, and bounded XID ring buffers to eliminate memory growth and router GC load.
- **Bilingual & 3-Step Simplified Installer**: Streamlined installation from 8 steps down to 3 steps with smart auto-detection, auto-start service management, and English/Chinese language selection.
- **Multi-Route Domestic Mirror Acceleration**: Built-in jsDelivr global CDN and domestic mirror nodes (`ghfast.top`, `ghproxy.net`) with automatic race/fallback for seamless downloads in mainland China.
- **Enhanced Observability & Privacy Protection**: Full MAC address masking (`mask_mac`) across all logs, status panels, and interactive prompts. Clear Wi-Fi reconnection guidance without misleading warnings.
- **Shortcuts Background Automation**: Documented iOS Shortcuts integration for 100% silent, background refresh upon connecting to home Wi-Fi.

## 0.5.3-public

- Optimized TUN reflector with zero-allocation RFC 1071 checksum calculation and hot-path allocation reduction.
- Implemented zero-allocation fast pre-filter on `AF_PACKET` to discard high-throughput non-DHCP LAN traffic instantly.
- Replaced unbounded XID map with bounded 16-slot ring buffer to prevent memory leakage.
- Completely redesigned `install.sh` with bilingual (Chinese/English) prompts, smart auto-detection, and a simplified 3-step quick installation flow.
- Added domestic GitHub mirror acceleration fallback in `install.sh` and `upgrade.sh`.
- Upgraded `status.sh` with live metrics: cumulative reflected packet counts, last active timestamps, and learned Wi-Fi ports.
- Cleaned up obsolete internal handoff files (`CODEX_GITHUB_HANDOFF.md`, `PUBLIC_RELEASE_NOTES.md`).

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
