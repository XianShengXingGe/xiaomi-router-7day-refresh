# Xiaomi Router 7-Day Refresh for SideStore / LiveContainer

## 中文

### 项目简介

这是一个运行在小米路由器 / OpenWrt 上的 SideStore / LiveContainer 路由器端辅助工具。

项目把发往 SideStore Override Peer `10.7.0.1` 的指定流量引导到路由器上的 TUN 反射器。反射器只交换 IPv4 源地址和目的地址，并重新计算 IPv4、TCP 或 UDP 校验和。这样，iPhone 连接家庭 Wi-Fi 时可以通过路由器完成所需的本地网络路径，而无需手机端 StosVPN / LocalDevVPN 持续接管所有流量。

本项目不替代 SideStore 或 LiveContainer，也不会绕过 Apple ID、证书、App ID、配对文件或 Anisette 的限制。

### 解决的需求

v0.5.x 只对配置中的一台 iPhone 生效，并支持两种常见家庭网络拓扑：

1. **主路由器模式**：iPhone 直接连接此路由器，且此路由器提供 DHCP 和默认网关。项目通过 dnsmasq 向目标 iPhone 下发 DHCP Option 121，将 `10.7.0.1/32` 指向此路由器。
2. **无线中继 / 子路由器模式**：iPhone 连接子路由器，而 DHCP 和默认网关由上级路由器提供。项目只修改目标 iPhone 的上级 DHCP ACK，注入 `10.7.0.1/32` 路由，同时保留原来的默认网关。
3. **窄范围处理**：两种模式都只将 `10.7.0.1/32` 路由到 `sidestore` TUN 接口；不会将 iPhone 的默认流量改道到本项目。
4. **可维护运行状态**：提供安装、升级、启动、状态、诊断和清理脚本；清理时只移除项目创建的路由、iptables 链、TUN 接口、进程和 dnsmasq 片段。

### 工作原理

```text
iPhone -> 10.7.0.1
             |
             v
      DHCP Option 121 主机路由
             |
             v
    路由器 sidestore TUN 反射器
             |
             v
10.7.0.1 -> iPhone 本地设备服务
```

反射器保留 TCP / UDP 端口，仅交换 IPv4 源地址和目的地址。这符合设备端服务所需的本地回环通信方式。

### 前提条件

通用要求：

- 受你控制的 Xiaomi / OpenWrt 路由器，已开启 root SSH
- `/dev/net/tun`、`ip`、`iptables`
- `linux/arm64` 或 `linux/amd64`
- iPhone 在该 Wi-Fi 下使用稳定的私有 Wi-Fi 地址 / MAC 地址

主路由器模式还需要 dnsmasq 作为 LAN DHCP 服务，并有可用的 `conf-dir`。无线中继 / 子路由器模式还需要 bridge netfilter、iptables `physdev`/`string` 匹配和 AF_PACKET 原始套接字支持。

### 安装与使用

在路由器 SSH 中直接从 GitHub 安装最新正式版本（旧版 BusyBox `wget` 不支持 HTTPS 时请使用已有的 `curl`）：

```sh
cd /tmp
rm -f xiaomi-router-7day-refresh-install.sh
curl -fLk -o xiaomi-router-7day-refresh-install.sh \
  'https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh'
sh xiaomi-router-7day-refresh-install.sh
```

更新到 GitHub 上的最新版本：

```sh
cd /tmp
rm -f xiaomi-router-7day-refresh-upgrade.sh
curl -fLk -o xiaomi-router-7day-refresh-upgrade.sh \
  'https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/upgrade.sh'
sh xiaomi-router-7day-refresh-upgrade.sh
```

`upgrade.sh` 会再次从 GitHub 下载最新的 `install.sh`，因此不依赖同目录存在旧安装器。也可以从 [Releases](https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases) 下载完整 Release 包，上传并解压到路由器后执行：

```sh
cd /tmp/xiaomi-router-7day-refresh-release
sh install.sh
```

安装器会询问网络拓扑、LAN/桥接接口、路由器 LAN IPv4、iPhone Wi-Fi MAC、TUN 接口，以及模式所需的 DHCP 参数。目标地址固定为 `10.7.0.1`。

首次安装、升级或切换拓扑后，请将 iPhone Wi-Fi 关闭再打开一次，以获取新的 DHCP 路由。

常用命令：

```sh
START_DELAY=2 /data/xiaomi-router-7day-refresh-start.sh
/data/xiaomi-router-7day-refresh-status.sh
/data/xiaomi-router-7day-refresh-diagnose.sh status
/data/xiaomi-router-7day-refresh-cleanup.sh
```

更多排查方法见 [故障排查](docs/troubleshooting.md) 和 [使用说明](docs/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.txt)。

### 安全与隐私

请只在自己拥有或明确获授权管理的网络中使用。本项目需要 root 权限，并会修改项目专属的路由、DHCP 和防火墙状态。

公开仓库不应提交真实 iPhone MAC、路由器 MAC、真实 LAN / 网关地址、路由器配置、日志、抓包、配对文件、凭据或令牌。文档中的 `<...>` 均为占位符；`10.7.0.1` 是项目使用的 SideStore Override Peer，不是用户的家庭网络地址。

### 鸣谢与参考

感谢下列项目、协议和资料为本项目提供思路或基础能力：

- [SideStore](https://sidestore.io/) 与 [LiveContainer](https://github.com/LiveContainer/LiveContainer)：本项目服务的刷新和本地设备通信场景。
- StosVPN / LocalDevVPN：对 SideStore 本地 VPN 通信路径的理解来源。
- [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn)：相关网络行为的参考。
- [OpenWrt](https://openwrt.org/)、dnsmasq、Linux TUN 和 iptables：实现路由、DHCP 和数据包处理所依赖的平台能力。
- [Juewuy 的小米路由器 SSH 教程](https://jwsc.eu.org/gDyfIPSsZ/)：小米路由器 SSH 场景的参考资料。

本项目与上述项目及作者没有从属、合作或官方认可关系。

### 构建

```sh
make test
make vet
make build
make release
```

许可证：MIT。

---

## English

### Project overview

This is a router-side helper for SideStore / LiveContainer on Xiaomi router and OpenWrt systems.

It directs traffic for the SideStore Override Peer, `10.7.0.1`, into a router-hosted TUN reflector. The reflector swaps only IPv4 source and destination addresses, then recalculates IPv4, TCP, or UDP checksums. When an iPhone joins the home Wi-Fi, this provides the required local-network path without requiring StosVPN / LocalDevVPN on the phone to continuously handle all traffic.

This project does not replace SideStore or LiveContainer, and it does not bypass Apple ID, certificate, App ID, pairing-file, or Anisette requirements.

### Requirements it addresses

v0.5.x applies only to the configured iPhone and supports two common home-network topologies:

1. **Main-router mode**: the iPhone connects directly to this router, which supplies DHCP and the default gateway. The project uses dnsmasq to send a targeted DHCP Option 121 route for `10.7.0.1/32` through this router.
2. **Wireless repeater / child-router mode**: the iPhone connects to the child router while an upstream router supplies DHCP and the default gateway. The project patches only the selected iPhone's upstream DHCP ACK, adds the `10.7.0.1/32` route, and preserves the original default gateway.
3. **Narrow traffic handling**: both modes route only `10.7.0.1/32` through the `sidestore` TUN interface; they do not redirect the iPhone's default traffic through this project.
4. **Maintainable runtime state**: install, upgrade, start, status, diagnostics, and cleanup scripts are included. Cleanup removes only project-owned routes, iptables chains, TUN interfaces, processes, and dnsmasq snippets.

### How it works

```text
iPhone -> 10.7.0.1
             |
             v
      DHCP Option 121 host route
             |
             v
     Router sidestore TUN reflector
             |
             v
10.7.0.1 -> iPhone local device service
```

The reflector keeps TCP / UDP ports unchanged and swaps only IPv4 source and destination addresses. This matches the local loopback-style communication expected by the device-side service.

### Prerequisites

Common requirements:

- A Xiaomi / OpenWrt router you control, with root SSH access
- `/dev/net/tun`, `ip`, and `iptables`
- `linux/arm64` or `linux/amd64`
- A stable Private Wi-Fi Address / MAC address for the iPhone on this Wi-Fi network

Main-router mode also requires dnsmasq as the LAN DHCP server and an active `conf-dir`. Wireless repeater / child-router mode also requires bridge netfilter, the iptables `physdev` and `string` matches, and AF_PACKET raw-socket support.

### Install and use

Install the latest published version directly from the router's SSH shell. Some older BusyBox `wget` builds do not support HTTPS, so use the available `curl`:

```sh
cd /tmp
rm -f xiaomi-router-7day-refresh-install.sh
curl -fLk -o xiaomi-router-7day-refresh-install.sh \
  'https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh'
sh xiaomi-router-7day-refresh-install.sh
```

Update to the latest GitHub version:

```sh
cd /tmp
rm -f xiaomi-router-7day-refresh-upgrade.sh
curl -fLk -o xiaomi-router-7day-refresh-upgrade.sh \
  'https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/upgrade.sh'
sh xiaomi-router-7day-refresh-upgrade.sh
```

`upgrade.sh` downloads the latest `install.sh` from GitHub before running it, so it does not depend on an older installer being beside it. You can also download the complete package from [Releases](https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases), upload and extract it on the router, then run:

```sh
cd /tmp/xiaomi-router-7day-refresh-release
sh install.sh
```

The installer asks for the topology, LAN/bridge interface, router LAN IPv4 address, iPhone Wi-Fi MAC, TUN interface, and mode-specific DHCP values. The target is fixed at `10.7.0.1`.

After the first installation, an upgrade, or a topology change, toggle iPhone Wi-Fi off and on once to receive the new DHCP route.

Common commands:

```sh
START_DELAY=2 /data/xiaomi-router-7day-refresh-start.sh
/data/xiaomi-router-7day-refresh-status.sh
/data/xiaomi-router-7day-refresh-diagnose.sh status
/data/xiaomi-router-7day-refresh-cleanup.sh
```

See [troubleshooting](docs/troubleshooting.md) and the [usage guide](docs/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.txt) for more detail.

### Security and privacy

Use this project only on networks you own or are explicitly authorized to manage. It requires root privileges and changes project-owned routing, DHCP, and firewall state.

Do not commit real iPhone MAC addresses, router MAC addresses, LAN / gateway addresses, router configurations, logs, packet captures, pairing files, credentials, or tokens. `<...>` values in the documentation are placeholders. `10.7.0.1` is the SideStore Override Peer used by this project, not a home-network address.

### Credits and references

Thanks to these projects, technologies, and materials for ideas or foundational capabilities:

- [SideStore](https://sidestore.io/) and [LiveContainer](https://github.com/LiveContainer/LiveContainer), the refresh and local-device communication scenarios this project supports.
- StosVPN / LocalDevVPN, which informed the understanding of SideStore's local VPN path.
- [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn), a reference for related network behavior.
- [OpenWrt](https://openwrt.org/), dnsmasq, Linux TUN, and iptables, which provide the routing, DHCP, and packet-processing platform capabilities.
- [Juewuy's Xiaomi router SSH guide](https://jwsc.eu.org/gDyfIPSsZ/), a reference for Xiaomi router SSH setups.

This project is not affiliated with, sponsored by, or officially endorsed by any of the projects or authors above.

### Build

```sh
make test
make vet
make build
make release
```

License: MIT.
