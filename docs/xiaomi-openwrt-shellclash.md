# Xiaomi OpenWrt + ShellClash Setup Notes / 小米 OpenWrt + ShellClash 部署说明

## 中文

### 说明

这是一份脱敏后的真实环境部署说明。个人 IP、完整日志、代理配置和设备标识信息已经移除。

### 目标

让 iPhone 连接家庭 Wi-Fi 后，可以配合路由器侧辅助程序自动触发 SideStore / LiveContainer 刷新流程，减少手动开启 StosVPN / LocalDevVPN 的步骤。

### 环境

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

### 尝试过但不理想的方案

#### 1. nftables

该路由器没有 `nft` 命令，因此无法直接使用基于 nftables 的简单方案。

#### 2. 纯 iptables DNAT/SNAT

最初尝试为一个固定 iPhone IP 设置 DNAT / SNAT 规则。DNAT 可以命中，但 SNAT 不稳定，因为 DNAT 后数据包可能变成类似 `<IPHONE_IP> -> <IPHONE_IP>` 的形态，后续转发路径不符合预期。

#### 3. 路由器侧 TUN 辅助程序

最终可用的方案是在路由器上运行 TUN 包改写程序：

```text
<IPHONE_IP> -> 10.7.0.1
```

改写为：

```text
10.7.0.1 -> <IPHONE_IP>
```

### 可工作的路由和防火墙状态

最终可工作的状态大致如下：

```text
10.7.0.1 dev sidestore
FORWARD: br-lan -> sidestore, <IPHONE_IP> -> 10.7.0.1 ACCEPT
FORWARD: sidestore -> br-lan, 10.7.0.1 -> <IPHONE_IP> ACCEPT
NAT PREROUTING: br-lan + 10.7.0.1 RETURN before ShellClash rules
```

### 关键注意事项

1. 在路由器 DHCP 设置里固定 iPhone 的局域网 IP。
2. 保持 NAT `RETURN` 规则位于 ShellClash NAT 规则之前。
3. 启动脚本里使用 `sleep 60`，等待 ShellClash 初始化完成后再插入规则。
4. 不建议长期使用 `-v` 运行二进制程序，详细日志可能填满 `/tmp`。
5. 如果网络异常，优先运行 `/data/xiaomi-router-7day-refresh-status.sh` 查看状态，再运行 `/data/xiaomi-router-7day-refresh-cleanup.sh` 清理规则。

## English

### Notes

This is a sanitized real-world setup note. Personal IPs, full logs, proxy configuration, and device-specific identifiers have been removed.

### Goal

Make SideStore / LiveContainer refresh flows work when the iPhone is connected to the home Wi-Fi, with the router-side helper reducing the need to manually start StosVPN / LocalDevVPN.

### Environment

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

### Approaches that did not work well

#### 1. nftables

The router did not have the `nft` command, so the simple nftables-based approach could not be used directly.

#### 2. Pure iptables DNAT/SNAT

An early attempt used DNAT / SNAT rules for one fixed iPhone IP. DNAT was hit, but SNAT was not reliable because after DNAT the packet could effectively become `<IPHONE_IP> -> <IPHONE_IP>`, making the later forwarding path behave unexpectedly.

#### 3. Router-side TUN helper

The working approach was to run a TUN packet rewriter on the router:

```text
<IPHONE_IP> -> 10.7.0.1
```

rewritten into:

```text
10.7.0.1 -> <IPHONE_IP>
```

### Working route and firewall state

The final working state looked conceptually like this:

```text
10.7.0.1 dev sidestore
FORWARD: br-lan -> sidestore, <IPHONE_IP> -> 10.7.0.1 ACCEPT
FORWARD: sidestore -> br-lan, 10.7.0.1 -> <IPHONE_IP> ACCEPT
NAT PREROUTING: br-lan + 10.7.0.1 RETURN before ShellClash rules
```

### Important details

1. Fix the iPhone LAN IP in the router DHCP settings.
2. Keep the NAT `RETURN` rule before ShellClash NAT rules.
3. Use `sleep 60` in the startup script so ShellClash finishes initializing before these rules are inserted.
4. Do not run the binary with `-v` for long-term use. Verbose logs can fill `/tmp`.
5. If the network behaves unexpectedly, start with `/data/xiaomi-router-7day-refresh-status.sh`, then use `/data/xiaomi-router-7day-refresh-cleanup.sh` to clean rules if needed.
