# Public release notes — v0.5.1-public

This package is prepared for publishing to GitHub.

## Privacy / desensitization

- No real iPhone Wi-Fi MAC address is embedded in source, tests, docs, or release scripts.
- No real router LAN IP, upstream gateway IP, or router MAC is embedded.
- Unit-test LAN addresses use RFC 5737 documentation addresses (`192.0.2.0/24`).
- Unit-test MAC addresses are locally administered synthetic fixtures.
- `10.7.0.1` is intentionally retained because it is the SideStore Override Peer used by the implementation, not a user-specific LAN address.
- `198.19.0.2` is retained only in migration/legacy cleanup documentation and code; it is not a user-specific identifier.
- Runtime configuration (`/data/xiaomi-router-7day-refresh.conf`), logs, PID files, backups, and debug captures are excluded by `.gitignore`.

## v0.5.1-public changes

- Keeps the validated dual-topology architecture from v0.5.0.
- Fixes `upgrade.sh` so it invokes `install.sh` through `sh`; this avoids `Permission denied` when executable bits are lost during Windows extraction/SFTP upload.
- Replaces environment-specific test fixtures with documentation/synthetic values.
- Adds publishing guardrails for Codex/GitHub sync.
