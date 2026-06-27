# Xiaomi Router 7-Day Refresh for SideStore / LiveContainer

## 中文

### 项目简介

这是一个面向小米路由器 / OpenWrt 环境的 SideStore / LiveContainer 7 天自动刷新辅助工具。开启路由器 SSH 后，你可以把本项目部署到路由器上，让路由器侧处理原本依赖 StosVPN / LocalDevVPN 的 `10.7.0.1` 局域网通信路径。

配合 iPhone 的“快捷指令 - 自动化”，可以在 iPhone 连接指定家庭 Wi-Fi 后触发 SideStore / LiveContainer 刷新流程，帮助你在 7 天有效期内自动刷新应用。

推荐使用方式：

1. 在小米路由器上开启 SSH。
2. 从 Windows、macOS 或 Linux 电脑 SSH 登录到路由器。
3. 在路由器 shell 里运行交互式安装脚本。
4. 让 iPhone 使用固定局域网 IP。
5. 使用 iOS 快捷指令自动化，在连接此 Wi-Fi 后触发 SideStore / LiveContainer 刷新。

本项目已在一台基于 OpenWrt 18.06 固件、安装 ShellClash 的小米路由器上验证。其他 OpenWrt 路由器如果提供 `/dev/net/tun`、`ip` 和 `iptables`，也可以自行尝试。

### 快速开始

#### 1. 准备 iPhone 和路由器

安装前，请先让 iPhone 的局域网 IP 保持稳定：

1. 在 iPhone 当前连接的 Wi-Fi 设置里，将 **私有无线局域网地址** 设置为 **固定** 或 **关闭**。
2. 在小米路由器后台开启并使用 **DHCP 静态 IP 分配**，把这台 iPhone 绑定到固定局域网 IP。

请记下这个固定 IP，例如 `192.168.31.100`。

#### 2. SSH 登录到路由器

如果你的小米路由器还没有开启 SSH，可以参考 Juewuy 的教程：[小米路由设备破解固化永久SSH教程](https://jwsc.eu.org/gDyfIPSsZ/)。不同型号和固件的操作方式可能不同，操作前请先确认教程适用于你的设备，并自行评估刷写、解锁或固化 SSH 的风险。

在电脑上打开 Terminal、Windows Terminal 或 PowerShell，然后 SSH 登录到路由器。

下面的地址只是示例：

```sh
ssh root@192.168.31.1
```

你的路由器地址不一定是 `192.168.31.1`，请使用你自己路由器的实际局域网 IP。

#### 3. 在路由器上运行安装脚本

进入路由器 shell 后运行：

```sh
cd /tmp
wget https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh
sh install.sh
```

安装脚本会交互式询问：

- iPhone 的固定局域网 IP
- LAN 接口名，通常是 `br-lan`
- TUN 接口名，通常是 `sidestore`
- 是否设置路由器开机自启动
- 是否立即启动服务

安装后会在 `/data` 下生成这些文件：

```text
/data/xiaomi-router-7day-refresh
/data/xiaomi-router-7day-refresh.conf
/data/xiaomi-router-7day-refresh-start.sh
/data/xiaomi-router-7day-refresh-status.sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

#### 4. 检查状态

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

关键结果应类似：

```text
[OK] helper process is running
[OK] TUN interface sidestore exists
[OK] TUN interface sidestore is up
[OK] route to 10.7.0.1 uses sidestore
```

#### 5. 添加 iOS 快捷指令自动化

路由器侧设置正常后，在 iPhone 上创建快捷指令自动化：

1. 触发条件：当 iPhone 连接到你的家庭 Wi-Fi。
2. 动作：打开 SideStore 或 LiveContainer。
3. 可选动作：运行你当前用于刷新 SideStore / LiveContainer 的快捷指令或 URL Scheme。

本项目只负责路由器侧网络路径。实际刷新仍然依赖 SideStore / LiveContainer、有效的 pairing file、本地网络权限，以及正常的 Apple ID / Anisette 状态。

### 工作原理

SideStore / LiveContainer 的刷新流程通常需要手机端 StosVPN / LocalDevVPN 处理与 `10.7.0.1` 相关的通信。

本项目把这部分包处理逻辑移动到路由器上：

```text
<IPHONE_IP> -> 10.7.0.1
```

改写为：

```text
10.7.0.1 -> <IPHONE_IP>
```

Go 程序会创建一个 TUN 接口，读取发往 `10.7.0.1` 的 IPv4 包，交换源 IP 和目标 IP，重新计算 IPv4 / TCP / UDP 校验和，然后把包写回 TUN。

### 项目状态

实验性项目。已在一个真实的小米 / OpenWrt / ShellClash 环境中验证。

本项目不做这些事：

- 不替代 SideStore 或 LiveContainer
- 不绕过 Apple ID、证书或 App ID 限制
- 不生成或替代 pairing file
- 不修复 Anisette 或 Apple 服务异常
- 不保证兼容所有 iOS、SideStore、LiveContainer 或 OpenWrt 版本

### 已验证环境

```text
Router: Xiaomi router / OpenWrt 18.06 based firmware
Kernel: Linux 4.4.x
Arch: aarch64
LAN interface: br-lan
TUN: /dev/net/tun available
Firewall: iptables
ShellClash: installed
Target IP: 10.7.0.1
```

### 安全说明

本工具需要路由器 root 权限，并会修改路由表和防火墙规则。请只在你拥有并可控的网络中使用。

### 手动构建

```bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dist/xiaomi-router-7day-refresh-linux-arm64 ./cmd/xiaomi-router-7day-refresh
```

或者：

```bash
make build-arm64
```

### 手动命令

启动：

```sh
/data/xiaomi-router-7day-refresh-start.sh
```

停止并清理规则：

```sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

查看状态：

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

### 排查问题

见 [docs/troubleshooting.md](docs/troubleshooting.md)。

### 相关下载与官网

- [Termius](https://termius.com/)：可用于从 Windows、macOS、Linux、iOS 或 Android 通过 SSH 登录路由器。
- [SideStore](https://sidestore.io/)：SideStore 官网。
- [SideStore Docs](https://docs.sidestore.io/)：SideStore 官方文档。
- [LiveContainer](https://github.com/LiveContainer/LiveContainer)：LiveContainer 官方 GitHub 仓库。
- [LiveContainer Releases](https://github.com/LiveContainer/LiveContainer/releases)：LiveContainer 发布下载页。

### 鸣谢

本项目受到以下项目和文章启发：

- SideStore / LocalDevVPN 行为
- StosVPN
- xddxdd/sidestore-vpn
- [Juewuy 的小米路由设备破解固化永久 SSH 教程](https://jwsc.eu.org/gDyfIPSsZ/)
- [蓝天关于跨局域网使用 SideStore 且不依赖 StosVPN 的文章](https://lantian.pub/article/modify-computer/sidestore-without-stosvpn-across-lan.lantian/)

本项目与 SideStore、LiveContainer、StosVPN、xddxdd、Juewuy 或蓝天没有从属关系。

### 许可证

MIT

---

## English

### Project Overview

This is a router-side 7-day refresh helper for SideStore / LiveContainer on Xiaomi router / OpenWrt environments. After enabling SSH on the router, you can deploy this project to handle the `10.7.0.1` LAN communication path that is normally provided by StosVPN / LocalDevVPN.

Combined with iOS Shortcuts automation, it can help trigger SideStore / LiveContainer refresh flows when the iPhone joins your home Wi-Fi, helping keep apps refreshed within the 7-day limit.

The intended setup is:

1. Enable SSH on the Xiaomi router.
2. SSH into the router from Windows, macOS, or Linux.
3. Run the interactive installer inside the router shell.
4. Keep the iPhone on a fixed LAN IP.
5. Use iOS Shortcuts automation to trigger SideStore / LiveContainer refresh after connecting to this Wi-Fi.

This project was tested on a Xiaomi router with OpenWrt 18.06 based firmware and ShellClash installed. Other OpenWrt routers may work if they provide `/dev/net/tun`, `ip`, and `iptables`.

### Quick Start

#### 1. Prepare the iPhone and router

Before installing, make the iPhone LAN IP stable:

1. On the iPhone, open the current Wi-Fi network settings and set **Private Wi-Fi Address** to **Fixed** or **Off**.
2. In the Xiaomi router admin page, enable and use **DHCP static IP assignment** to bind this iPhone to a fixed LAN IP.

Write down that fixed iPhone IP, for example `192.168.31.100`.

#### 2. SSH into the router

If SSH is not enabled on your Xiaomi router yet, you can refer to Juewuy's guide: [Xiaomi router permanent SSH tutorial](https://jwsc.eu.org/gDyfIPSsZ/). Steps may differ across router models and firmware versions. Make sure the guide applies to your device and evaluate the risks of unlocking, flashing, or making SSH persistent before proceeding.

Open Terminal, Windows Terminal, or PowerShell on your computer, then SSH into the router.

This address is only an example:

```sh
ssh root@192.168.31.1
```

Your router address may be different. Use the actual LAN IP of your router.

#### 3. Run the installer on the router

After you are inside the router shell, run:

```sh
cd /tmp
wget https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh
sh install.sh
```

The installer will ask for:

- the iPhone fixed LAN IP
- the LAN interface name, usually `br-lan`
- the TUN interface name, usually `sidestore`
- whether to enable auto start on router boot
- whether to start the helper immediately

It installs files under `/data`:

```text
/data/xiaomi-router-7day-refresh
/data/xiaomi-router-7day-refresh.conf
/data/xiaomi-router-7day-refresh-start.sh
/data/xiaomi-router-7day-refresh-status.sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

#### 4. Check status

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

Expected key results:

```text
[OK] helper process is running
[OK] TUN interface sidestore exists
[OK] TUN interface sidestore is up
[OK] route to 10.7.0.1 uses sidestore
```

#### 5. Add iOS Shortcuts automation

After router-side setup is working, create an iOS Shortcuts automation:

1. Trigger: when the iPhone joins your home Wi-Fi.
2. Action: open SideStore or LiveContainer.
3. Optional action: run the refresh shortcut or URL scheme you already use for your setup.

The router helper only handles the network path. The actual refresh still depends on SideStore / LiveContainer, a valid pairing file, local network permission, and a healthy Apple ID / Anisette state.

### What It Does

SideStore / LiveContainer refresh flows normally depend on the phone-side StosVPN / LocalDevVPN path for traffic involving `10.7.0.1`.

This helper moves that small packet-handling job to the router:

```text
<IPHONE_IP> -> 10.7.0.1
```

becomes:

```text
10.7.0.1 -> <IPHONE_IP>
```

The Go program opens a TUN interface, reads IPv4 packets sent to `10.7.0.1`, swaps the source and destination IP addresses, recalculates IPv4/TCP/UDP checksums, and writes the packet back.

### Status

Experimental. Tested in one real Xiaomi/OpenWrt/ShellClash environment.

This project does not:

- replace SideStore or LiveContainer
- bypass Apple ID, certificate, or App ID limits
- generate or replace pairing files
- fix Anisette or Apple service errors
- guarantee compatibility with every iOS, SideStore, LiveContainer, or OpenWrt version

### Tested Environment

```text
Router: Xiaomi router / OpenWrt 18.06 based firmware
Kernel: Linux 4.4.x
Arch: aarch64
LAN interface: br-lan
TUN: /dev/net/tun available
Firewall: iptables
ShellClash: installed
Target IP: 10.7.0.1
```

### Security Notes

This tool requires root access on the router and changes routing/firewall behavior. Use it only on networks you control.

### Manual Build

```bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dist/xiaomi-router-7day-refresh-linux-arm64 ./cmd/xiaomi-router-7day-refresh
```

Or:

```bash
make build-arm64
```

### Manual Commands

Start:

```sh
/data/xiaomi-router-7day-refresh-start.sh
```

Stop and clean rules:

```sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

Status:

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

### Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

### Official Links

- [Termius](https://termius.com/) - SSH client for connecting to the router from Windows, macOS, Linux, iOS, or Android.
- [SideStore](https://sidestore.io/) - official SideStore website.
- [SideStore Docs](https://docs.sidestore.io/) - official SideStore documentation.
- [LiveContainer](https://github.com/LiveContainer/LiveContainer) - official LiveContainer GitHub repository.
- [LiveContainer Releases](https://github.com/LiveContainer/LiveContainer/releases) - LiveContainer release downloads.

### Credits

Inspired by:

- SideStore / LocalDevVPN behavior
- StosVPN
- xddxdd/sidestore-vpn
- [Juewuy's Xiaomi router permanent SSH tutorial](https://jwsc.eu.org/gDyfIPSsZ/)
- [Lan Tian's write-up on using SideStore without StosVPN across LAN](https://lantian.pub/article/modify-computer/sidestore-without-stosvpn-across-lan.lantian/)

This project is not affiliated with SideStore, LiveContainer, StosVPN, xddxdd, Juewuy, or Lantian.

### License

MIT
