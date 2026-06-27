# Project Background / 项目背景

## 中文

### 项目名称

**xiaomi-router-autosign**

### 一句话说明

这是一个面向 OpenWrt / 小米路由器环境的 SideStore / LiveContainer 局域网刷新辅助工具。它通过在路由器上创建 TUN 虚拟网卡，并处理发往 `10.7.0.1` 的流量，让 iPhone 在连接家庭 Wi-Fi 时可以完成 SideStore / LiveContainer 所需的 LocalDevVPN 类通信流程，减少对手机端 StosVPN 的依赖。

### 项目初衷

SideStore / LiveContainer 在刷新 App 时，通常需要 iPhone 端开启 StosVPN / LocalDevVPN。这个方案本身可用，但在日常使用中有几个不便：

1. 每次刷新前需要手动确认 VPN 状态。
2. VPN 可能与其他代理、分流或网络工具产生冲突。
3. 家庭 Wi-Fi 场景下，路由器通常已经具备持续在线、可控、可转发流量的条件。
4. 如果能把这部分网络处理逻辑放到路由器上，iPhone 连接家里 Wi-Fi 后就可以更接近“自动可用”的体验。

因此，这个项目的目标不是替代 SideStore / LiveContainer，也不是绕过认证或签名机制，而是把原本在 iPhone 端 VPN 中完成的局域网包处理逻辑，转移到可控的路由器环境中执行。

### 背景信息

SideStore / LiveContainer 的刷新流程需要让 iPhone 与特殊地址 `10.7.0.1` 通信。StosVPN / LocalDevVPN 的核心作用之一，是让 iPhone 发往 `10.7.0.1` 的网络包经过特殊处理后，再返回给 iPhone 本机。

本项目的实现思路是：

```text
iPhone: 192.168.31.x -> 10.7.0.1
        |
OpenWrt router / TUN interface
        |
10.7.0.1 -> 192.168.31.x
```

也就是：

- iPhone 访问 `10.7.0.1`。
- 路由器把 `10.7.0.1/32` 路由到本地 TUN 虚拟网卡。
- 程序从 TUN 读取 IPv4 包。
- 程序交换源 IP 与目标 IP。
- 程序重新计算 IPv4 / TCP / UDP 校验和。
- 程序把包写回 TUN。
- 路由器再把处理后的包转发回 iPhone。

这样，iPhone 可以收到一个“来自 `10.7.0.1`”的响应包，从而满足 LocalDevVPN 类通信路径的要求。

### 解决的问题

#### 1. 没有 nftables 的旧 OpenWrt 路由器无法直接使用 nft 方案

很多方案依赖 `nftables`，通过 nft 规则完成源 / 目的 IP 交换。但部分小米路由器或定制 OpenWrt 环境中没有 `nft` 命令，直接安装 nftables 也可能遇到内核模块不匹配、空间不足或系统不稳定等问题。

本项目避开对 `nftables` 的依赖，改为使用用户态 TUN 程序完成包改写。

#### 2. 传统 iptables DNAT/SNAT 很难完整模拟 LocalDevVPN 行为

实际测试中，单纯用 `iptables` 做 DNAT / SNAT 可能出现 DNAT 命中但 SNAT 不稳定、FORWARD 路径不符合预期等情况。

根本原因是：传统 `iptables` 更适合做固定地址转换，不适合在这个场景下完成“源 IP / 目的 IP 互换”这种更像包重写的操作。

本项目将核心逻辑放到用户态程序里完成，避免依赖复杂的 iptables NAT 组合。

#### 3. ShellClash 环境下需要避免代理规则接管 `10.7.0.1`

很多 OpenWrt 用户会在路由器上运行 ShellClash。ShellClash 会接管部分 NAT / PREROUTING 规则，如果不处理，发往 `10.7.0.1` 的流量可能被代理规则干扰。

本项目的启动脚本会插入规则：

```sh
iptables -t nat -I PREROUTING 1 -i br-lan -d 10.7.0.1 -j RETURN
```

这条规则的目的，是让发往 `10.7.0.1` 的流量优先跳过 ShellClash 的透明代理处理。

#### 4. 让家庭 Wi-Fi 下的刷新更接近自动化

部署完成后，只要：

- iPhone 连接同一个家庭 Wi-Fi。
- iPhone 局域网 IP 固定。
- 路由器上的程序和自启动脚本正常。
- SideStore / LiveContainer、pairing file、本地网络权限、Apple ID / Anisette 状态正常。

就可以配合 iOS 快捷指令，在连接家庭 Wi-Fi 后触发刷新流程。

### 已验证环境

```text
Router:
- Xiaomi router
- OpenWrt 18.06 based firmware
- Linux 4.4.x
- aarch64
- ShellClash installed
- /dev/net/tun available

iPhone:
- Connected to the same LAN
- Fixed LAN IP required
- SideStore / LiveContainer installed
- Pairing file configured
```

不同路由器、不同 OpenWrt 版本、不同 ShellClash 模式下，规则顺序和接口名称可能不同，需要根据实际环境调整。

### 项目不解决的问题

本项目不解决以下问题：

1. 不提供 SideStore / LiveContainer 安装服务。
2. 不绕过 Apple ID、签名、证书或 App ID 限制。
3. 不生成或替代 pairing file。
4. 不处理 Anisette 服务异常。
5. 不保证所有 iOS / SideStore / LiveContainer 版本均兼容。
6. 不建议在非本人可控网络中部署。

如果报错属于 Apple ID、Anisette、pairing file 或 App ID limit 等问题，需要先在 SideStore / LiveContainer 本身排查。

### 核心文件

```text
cmd/xiaomi-router-autosign/main.go
```

用户态 TUN 程序，负责读取、改写、写回 IPv4 包。

```text
scripts/install.sh
```

交互式安装脚本，用于下载二进制、生成配置、安装辅助脚本，并可选设置开机自启动。

```text
scripts/start.sh
```

OpenWrt 启动脚本，负责启动程序、设置路由、插入 iptables 规则。

```text
scripts/status.sh
```

状态检查脚本，用于确认进程、TUN 接口、路由和防火墙规则是否正常。

```text
scripts/cleanup.sh
```

清理脚本，用于停止程序并删除相关临时规则。

### 典型部署效果

部署成功后，检查状态应类似：

```text
/data/xiaomi-router-autosign -iface sidestore -target 10.7.0.1
10.7.0.1 dev sidestore
FORWARD: br-lan -> sidestore
FORWARD: sidestore -> br-lan
NAT PREROUTING: RETURN br-lan 10.7.0.1
```

当 iPhone 刷新 SideStore / LiveContainer 时，FORWARD 计数会增长，说明流量已经经过路由器上的 TUN 处理流程。

### 免责声明

本项目需要 root 权限，并会修改路由器的路由表和防火墙规则。请仅在本人拥有和可控的网络环境中使用。

使用前建议先理解脚本内容，并准备好 SSH 访问方式，以便在网络异常时手动清理规则或重启路由器。

本项目仅用于学习、研究和改善个人设备在家庭局域网中的使用体验。

## English

### Project name

**xiaomi-router-autosign**

### One-sentence summary

This is a LAN refresh helper for SideStore / LiveContainer on OpenWrt / Xiaomi router environments. It creates a TUN interface on the router and handles traffic sent to `10.7.0.1`, allowing an iPhone connected to the home Wi-Fi to complete the LocalDevVPN-style communication flow required by SideStore / LiveContainer while reducing reliance on phone-side StosVPN.

### Motivation

When refreshing apps, SideStore / LiveContainer usually requires StosVPN / LocalDevVPN on the iPhone. That works, but it has some daily-use friction:

1. You need to manually check VPN state before refreshing.
2. The VPN may conflict with other proxy, split-routing, or network tools.
3. In a home Wi-Fi environment, the router is already always on, controllable, and able to forward traffic.
4. Moving this network handling logic to the router can make the iPhone experience closer to automatic availability when joining the home Wi-Fi.

The goal of this project is not to replace SideStore / LiveContainer, nor to bypass authentication or signing mechanisms. It only moves the LAN packet handling that would normally happen inside the iPhone-side VPN into a controllable router environment.

### Background

The refresh flow needs the iPhone to communicate with the special address `10.7.0.1`. One core role of StosVPN / LocalDevVPN is to process packets sent from the iPhone to `10.7.0.1` and return them to the iPhone.

The implementation idea is:

```text
iPhone: 192.168.31.x -> 10.7.0.1
        |
OpenWrt router / TUN interface
        |
10.7.0.1 -> 192.168.31.x
```

In other words:

- The iPhone accesses `10.7.0.1`.
- The router routes `10.7.0.1/32` to a local TUN interface.
- The program reads IPv4 packets from TUN.
- The program swaps source and destination IP addresses.
- The program recalculates IPv4 / TCP / UDP checksums.
- The program writes the packet back to TUN.
- The router forwards the rewritten packet back to the iPhone.

This lets the iPhone receive a response packet "from `10.7.0.1`", satisfying the LocalDevVPN-style communication path.

### Problems solved

#### 1. Older OpenWrt routers without nftables cannot use nft-based approaches directly

Many approaches rely on `nftables` to swap source and destination IP addresses with nft rules. Some Xiaomi router or custom OpenWrt environments do not have the `nft` command, and installing nftables may run into kernel module mismatch, storage limits, or stability risks.

This project avoids the nftables dependency and uses a user-space TUN program for packet rewriting.

#### 2. Traditional iptables DNAT/SNAT is not a complete fit for LocalDevVPN behavior

In practice, pure `iptables` DNAT / SNAT can hit DNAT while SNAT remains unreliable, or the FORWARD path may not behave as expected.

The root reason is that traditional `iptables` is better suited for fixed address translation, while this scenario needs source / destination IP swapping, which is closer to packet rewriting.

This project moves the core logic into a user-space program and avoids complex iptables NAT combinations.

#### 3. ShellClash environments need to bypass proxy rules for `10.7.0.1`

Many OpenWrt users run ShellClash on the router. ShellClash may take over NAT / PREROUTING rules. Without handling this, traffic to `10.7.0.1` may be intercepted by proxy rules.

The startup script inserts:

```sh
iptables -t nat -I PREROUTING 1 -i br-lan -d 10.7.0.1 -j RETURN
```

This makes traffic to `10.7.0.1` skip ShellClash transparent proxy handling first.

#### 4. Make home Wi-Fi refresh flows closer to automation

After deployment, if:

- the iPhone is connected to the same home Wi-Fi,
- the iPhone LAN IP is fixed,
- the router helper and startup script are working,
- SideStore / LiveContainer, pairing file, Local Network permission, and Apple ID / Anisette state are healthy,

then iOS Shortcuts can trigger the refresh flow after joining the home Wi-Fi.

### Tested environment

```text
Router:
- Xiaomi router
- OpenWrt 18.06 based firmware
- Linux 4.4.x
- aarch64
- ShellClash installed
- /dev/net/tun available

iPhone:
- Connected to the same LAN
- Fixed LAN IP required
- SideStore / LiveContainer installed
- Pairing file configured
```

Different routers, OpenWrt versions, and ShellClash modes may require adjusting rule order and interface names.

### What this project does not solve

This project does not:

1. provide SideStore / LiveContainer installation service,
2. bypass Apple ID, signing, certificate, or App ID limits,
3. generate or replace pairing files,
4. handle Anisette service failures,
5. guarantee compatibility with every iOS / SideStore / LiveContainer version,
6. recommend deployment on networks you do not control.

If an error belongs to Apple ID, Anisette, pairing file, or App ID limit issues, troubleshoot SideStore / LiveContainer first.

### Core files

```text
cmd/xiaomi-router-autosign/main.go
```

User-space TUN program for reading, rewriting, and writing back IPv4 packets.

```text
scripts/install.sh
```

Interactive installer that downloads the binary, writes configuration, installs helper scripts, and can optionally enable auto start.

```text
scripts/start.sh
```

OpenWrt startup script that starts the program, sets routes, and inserts iptables rules.

```text
scripts/status.sh
```

Status script that checks the process, TUN interface, route, and firewall rules.

```text
scripts/cleanup.sh
```

Cleanup script that stops the program and removes temporary rules.

### Typical deployment result

After successful deployment, status should look conceptually like:

```text
/data/xiaomi-router-autosign -iface sidestore -target 10.7.0.1
10.7.0.1 dev sidestore
FORWARD: br-lan -> sidestore
FORWARD: sidestore -> br-lan
NAT PREROUTING: RETURN br-lan 10.7.0.1
```

When the iPhone refreshes SideStore / LiveContainer, FORWARD counters should increase, showing that traffic is passing through the router-side TUN flow.

### Disclaimer

This project requires root privileges and modifies the router routing table and firewall rules. Use it only in networks you own and control.

Before using it, read the scripts and make sure SSH access is available, so you can manually clean rules or reboot the router if networking behaves unexpectedly.

This project is intended only for learning, research, and improving the experience of personal devices in a home LAN.
