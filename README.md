# Xiaomi Router 7-Day Refresh for SideStore / LiveContainer

Router-side helper for SideStore / LiveContainer refresh workflows on Xiaomi/OpenWrt routers.

## v0.5.1 public release

The validated SideStore endpoint is now the **Override Peer IP `10.7.0.1`**.

The previous v0.4 experiment routed the auto-discovered Local VPN peer (`198.19.0.2`). That proved DHCP Option 121 and the router reflector worked, but SideStore could still keep its internal Device Endpoint uninitialized when an explicit override was configured.

v0.5.x follows SideStore's override path instead:

```text
SideStore
   |
   | Override Peer = 10.7.0.1
   v
router-side host route / reflector
   |
   v
iPhone local device service
```

This path has been validated end-to-end on a wireless-repeater topology. No device-specific MAC address, LAN address, or router identifier is embedded in the public source.

## Supported topologies

### Mode 1 — Main router

Use this when the iPhone connects directly to the router and this router is also the DHCP server/default gateway.

```text
iPhone
  |
  v
Xiaomi/OpenWrt main router
  |
  v
Internet
```

The project installs a MAC-targeted dnsmasq DHCP Option 121 entry for the selected iPhone:

```text
10.7.0.1/32 -> this router LAN IP
0.0.0.0/0   -> this router LAN IP
```

The router then routes `10.7.0.1/32` into the project TUN reflector.

### Mode 2 — Wireless repeater / child router

Use this when the iPhone connects to a child/repeater router, while DHCP/default gateway are provided by an upstream router.

```text
iPhone
  |
  v
Xiaomi child router / wireless repeater
  |
  v
upstream main router (actual DHCP/default gateway)
```

Because the child router is not the DHCP server, editing its dnsmasq configuration cannot change the iPhone lease. The project therefore:

1. Watches bridged DHCP traffic with an AF_PACKET raw socket.
2. Learns the actual phone-facing Wi-Fi bridge member from the iPhone DHCP Request.
3. Observes the upstream DHCP ACK.
4. Patches only the ACK for the configured iPhone Wi-Fi MAC.
5. Adds Option 121:
   - `10.7.0.1/32 -> child router LAN IP`
   - `0.0.0.0/0 -> upstream default gateway`
6. Sends the patched ACK directly back to the learned phone-facing interface.
7. Drops only the original unpatched ACK for that iPhone; OFFER/NAK packets are not blocked.
8. Routes `10.7.0.1/32` into the same TUN reflector as Mode 1.

If the upstream ACK already contains Option 121, the injector prepends the SideStore `/32` route and preserves the existing Option 121 payload.

## Reflector behavior

Both modes use the same narrow reflector:

```text
phone-ip:client-port -> 10.7.0.1:device-port
                 |
                 v
             sidestore TUN
                 |
       swap IPv4 src/dst only
       recalculate IPv4/TCP/UDP checksums
                 |
                 v
10.7.0.1:client-port -> phone-ip:device-port
```

TCP/UDP ports are intentionally not swapped. This matches the loopback-reflection behavior required by the device-side service.

## SideStore expectation

This release is designed for SideStore Local VPN / Remote Pairing where Connection Configuration shows:

```text
Override Peer IP: 10.7.0.1
```

The router can make that address reachable, but it cannot change SideStore's internal configuration. If a SideStore build uses a different/empty override address, update/configure SideStore accordingly before expecting this router target to become active.

## Requirements

Common:

- root/SSH access on the router
- Linux/OpenWrt-like system
- `/dev/net/tun`
- `ip`
- `iptables`
- ARM64 or AMD64

Mode 1 additionally requires:

- dnsmasq as LAN DHCP server
- active dnsmasq `conf-dir`

Mode 2 additionally requires:

- bridge netfilter (`/proc/sys/net/bridge/bridge-nf-call-iptables`)
- `iptables` `physdev` match
- `iptables` `string` match
- AF_PACKET raw sockets (`CONFIG_PACKET`)

## Installation

Upload/extract the release bundle on the router, then:

```sh
cd /tmp/xiaomi-router-7day-refresh-release
sh install.sh
```

The installer asks for:

- topology: Main router or Wireless repeater / child router
- LAN/bridge interface, usually `br-lan`
- this router LAN IPv4
- iPhone Wi-Fi MAC / Private Wi-Fi Address for this SSID
- TUN interface name, usually `sidestore`
- Mode 1: active dnsmasq `conf-dir`
- Mode 2: upstream/default gateway IPv4

The target is fixed to:

```text
10.7.0.1
```

After first installation or after changing topology, toggle the iPhone Wi-Fi OFF/ON once so a fresh DHCP ACK can install the `/32` route.

## Installed files

```text
/data/xiaomi-router-7day-refresh
/data/xiaomi-router-7day-refresh.conf
/data/xiaomi-router-7day-refresh-start.sh
/data/xiaomi-router-7day-refresh-status.sh
/data/xiaomi-router-7day-refresh-cleanup.sh
/data/xiaomi-router-7day-refresh-diagnose.sh
```

## Commands

Manual start with a short delay:

```sh
START_DELAY=2 /data/xiaomi-router-7day-refresh-start.sh
```

`START_DELAY=2` only shortens the startup wait. The important v0.5 behavior is that the loaded config uses `TARGET="10.7.0.1"`.

Status:

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

Diagnostics:

```sh
/data/xiaomi-router-7day-refresh-diagnose.sh status
/data/xiaomi-router-7day-refresh-diagnose.sh watch-dhcp
/data/xiaomi-router-7day-refresh-diagnose.sh watch-target
```

Stop and clean:

```sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

## Expected success indicators

Mode 1:

```text
[OK] targeted DHCP Option121 snippet exists
[OK] reflector process is running
[OK] router route 10.7.0.1/32 uses sidestore
```

Mode 2:

```text
learned iPhone ingress interface: wl...
INJECTED DHCP ACK ... Option121 10.7.0.1/32 via <child-router-ip> + default via <upstream-gateway>
```

After SideStore Refresh:

```text
reflector rewrote packet #...
```

In SideStore Health Check, the desired state is that `Override Peer IP` is `10.7.0.1` and becomes reachable/active.

## Upgrade from v0.4

v0.4 used `198.19.0.2`. v0.5 migrates to SideStore's explicit override endpoint `10.7.0.1`.

Run:

```sh
sh upgrade.sh
```

The installer cleans the previous runtime, writes the new target, and asks for the current topology. The v0.5 cleanup/start scripts also remove legacy `198.19.0.2` route/bypass state when present.

## Safety / rollback

The cleanup script removes only project-owned runtime state:

- project TUN route/interface
- DHCP ACK interception rules
- DHCP injector/reflector processes
- project-owned dnsmasq snippet
- project-owned reflector/NAT/mangle exceptions
- legacy v0.4 `198.19.0.2` route/bypass state

It does not change Apple account/certificate limits, create pairing files, or modify the upstream main router in repeater mode.

## Build

```sh
make test
make vet
make build
```

Release bundle:

```sh
make release
```

## License

MIT
