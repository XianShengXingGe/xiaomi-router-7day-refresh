# Xiaomi OpenWrt + ShellClash setup notes

This is a sanitized real-world setup note. Personal IPs, full logs, proxy configuration, and device-specific identifiers have been removed.

## Goal

Make SideStore refresh work automatically when the iPhone is connected to the home Wi-Fi, without manually enabling StosVPN/LocalDevVPN.

## Environment

```text
Router OS: Xiaomi router firmware based on OpenWrt 18.06-SNAPSHOT
Kernel: Linux 4.4.x
Arch: aarch64
Package manager: opkg exists
nftables: unavailable
iptables: available
TUN: /dev/net/tun available
LAN interface: br-lan
ShellClash: installed
```

## Failed approaches

### 1. nftables

The router did not have the `nft` command, so the simple nftables approach could not be used.

### 2. Pure iptables DNAT/SNAT

A first attempt used DNAT/SNAT rules for one fixed iPhone IP. DNAT was hit, but SNAT did not reliably run because after DNAT the packet effectively became `<IPHONE_IP> -> <IPHONE_IP>`.

### 3. Router-side TUN helper

The working approach was to run a TUN packet rewriter on the router:

```text
<IPHONE_IP> -> 10.7.0.1
```

rewritten into:

```text
10.7.0.1 -> <IPHONE_IP>
```

## Working route/firewall state

The final working state looked like this conceptually:

```text
10.7.0.1 dev sidestore
FORWARD: br-lan -> sidestore, <IPHONE_IP> -> 10.7.0.1 ACCEPT
FORWARD: sidestore -> br-lan, 10.7.0.1 -> <IPHONE_IP> ACCEPT
NAT PREROUTING: br-lan + 10.7.0.1 RETURN before ShellClash rules
```

## Important details

1. Fix the iPhone LAN IP in the router DHCP settings.
2. Keep the NAT `RETURN` rule before ShellClash NAT rules.
3. Use `sleep 60` in the startup script so ShellClash finishes initializing before these rules are inserted.
4. Do not run the binary with `-v` for long-term use. Verbose logs can fill `/tmp`.
5. Do not upload pairing files, Apple ID data, or Clash configuration to any public repo.
