# Codex handoff: sync this package to GitHub

Use this directory as the source of truth for the public repository update.

## Goal

Publish `v0.5.1-public` of `xiaomi-router-7day-refresh` while preserving the existing repository history.

## Required steps

1. Inspect the current GitHub working tree and compare it with this package.
2. Copy/update source files from this package into the repository; do not copy local router configs, logs, packet captures, PID files, or backup files.
3. Preserve the MIT license and existing repository name unless explicitly instructed otherwise.
4. Run:
   - `go test ./...`
   - `go vet ./...`
   - `sh -n scripts/install.sh scripts/upgrade.sh scripts/start.sh scripts/status.sh scripts/cleanup.sh scripts/diagnose.sh`
5. Build release binaries with the Makefile or GitHub Actions workflow.
6. Verify `grep -R` finds no real device MAC addresses or environment-specific LAN/gateway addresses.
7. Commit the source update with a clear message such as `release: v0.5.1 public dual-topology SideStore refresh`.
8. Push only after reviewing the diff.

## Do not publish

- `/data/xiaomi-router-7day-refresh.conf` or any copy of it
- router logs or tcpdump output
- DHCP captures
- real iPhone/router MAC addresses
- real private LAN IPs or upstream gateway details
- local SSH credentials, tokens, or shell history

## Architecture to preserve

- Mode 1: main router supplies MAC-targeted DHCP Option 121.
- Mode 2: wireless repeater/child router patches only the target phone's upstream DHCP ACK and injects Option 121.
- Both modes route SideStore Override Peer `10.7.0.1/32` into the same narrow TUN reflector.
- The reflector swaps IPv4 source/destination addresses only and recalculates IPv4/TCP/UDP checksums; transport ports are intentionally not swapped.
