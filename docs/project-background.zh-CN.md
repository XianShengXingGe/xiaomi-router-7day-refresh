# 项目初衷、背景与问题说明

## 项目名称

**xiaomi-router-autosign**

## 一句话说明

这是一个面向 OpenWrt / 小米路由器环境的 SideStore 局域网刷新辅助工具。它通过在路由器上创建 TUN 虚拟网卡，并处理发往 `10.7.0.1` 的流量，让 iPhone 在连接家庭 Wi-Fi 时可以完成 SideStore 所需的 LocalDevVPN 类通信流程，减少对手机端 StosVPN 的依赖。

## 项目初衷

SideStore 在刷新 App 时，通常需要 iPhone 端开启 StosVPN / LocalDevVPN。这个方案本身可用，但在日常使用中有几个不便：

1. 每次刷新前需要手动确认 VPN 状态；
2. VPN 可能与其他代理、分流、网络工具产生冲突；
3. 家庭 Wi-Fi 场景下，理论上路由器已经具备持续在线、可控、可转发流量的条件；
4. 如果能把这部分网络处理逻辑放到路由器上，iPhone 连接家里 Wi-Fi 后就可以更接近“自动可用”的体验。

因此，这个项目的目标不是替代 SideStore，也不是绕过 SideStore 的认证或签名机制，而是把原本在 iPhone 端 VPN 中完成的局域网包处理逻辑，转移到可控的路由器环境中执行。

## 背景信息

SideStore 的刷新流程需要让 iPhone 与一个特殊地址 `10.7.0.1` 通信。StosVPN / LocalDevVPN 的核心作用之一，是让 iPhone 发往 `10.7.0.1` 的网络包经过特殊处理后，再返回给 iPhone 本机。

这个项目的实现思路是：

```text
iPhone: 192.168.31.x → 10.7.0.1
        ↓
OpenWrt router / TUN interface
        ↓
10.7.0.1 → 192.168.31.x
```

也就是：

- iPhone 访问 `10.7.0.1`；
- 路由器把 `10.7.0.1/32` 路由到本地 TUN 虚拟网卡；
- 程序从 TUN 读取 IPv4 包；
- 程序交换源 IP 与目标 IP；
- 程序重新计算 IPv4 / TCP / UDP 校验和；
- 程序把包写回 TUN；
- 路由器再把处理后的包转发回 iPhone。

这样，iPhone 可以收到一个“来自 `10.7.0.1`”的响应包，从而满足 SideStore 对 LocalDevVPN 通信路径的要求。

## 解决了什么问题

这个项目主要解决的是：

### 1. 没有 nftables 的旧 OpenWrt 路由器无法直接使用 nft 方案

很多文章给出的方案依赖 `nftables`，通过一条 nft 规则完成源/目的 IP 交换。

但部分小米路由器 / 定制 OpenWrt 环境中：

```text
nft: not found
```

同时内核较旧，直接安装 `nftables` 可能存在模块不匹配、空间不足、系统不稳定等风险。

本项目避开了对 `nftables` 的依赖，改为使用用户态 TUN 程序完成包改写。

### 2. 传统 iptables DNAT/SNAT 很难完整模拟 LocalDevVPN 行为

实际测试中，单纯用 `iptables` 做 DNAT / SNAT 会遇到问题：

```text
PREROUTING DNAT 可以命中
POSTROUTING SNAT 不一定命中
FORWARD 可能不按预期走
```

根本原因是：传统 `iptables` 更适合做固定地址转换，不适合在这个场景下完成“源 IP / 目的 IP 互换”这种更像包重写的操作。

本项目将核心逻辑放到用户态程序里完成，避免依赖复杂的 iptables NAT 组合。

### 3. ShellClash 环境下需要避免代理规则接管 `10.7.0.1`

很多 OpenWrt 用户会在路由器上运行 ShellClash。ShellClash 会接管部分 NAT / PREROUTING 规则，如果不处理，发往 `10.7.0.1` 的流量可能被代理规则干扰。

本项目提供启动脚本，自动插入规则：

```sh
iptables -t nat -I PREROUTING 1 -i br-lan -d 10.7.0.1 -j RETURN
```

这条规则的目的，是让发往 `10.7.0.1` 的流量优先跳过 ShellClash 的透明代理处理。

### 4. 让 SideStore 在家庭 Wi-Fi 下更接近“自动可用”

部署完成后，只要：

- iPhone 连接同一个家庭 Wi-Fi；
- iPhone 局域网 IP 固定；
- 路由器上的程序和自启动脚本正常；
- SideStore pairing、Local Network 权限、Apple ID 状态正常；

就可以在不手动开启 StosVPN 的情况下进行 SideStore 刷新。

## 已验证环境

本项目曾在以下环境中验证通过：

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
- SideStore installed
- Pairing file configured
```

注意：不同路由器、不同 OpenWrt 版本、不同 ShellClash 模式下，规则顺序和接口名称可能不同，需要根据实际环境调整。

## 项目不解决什么问题

本项目不解决以下问题：

1. 不提供 SideStore 安装服务；
2. 不绕过 Apple ID、签名、证书、App ID 限制；
3. 不生成或替代 pairing file；
4. 不处理 Anisette 服务异常；
5. 不保证所有 iOS / SideStore 版本均兼容；
6. 不建议在非本人可控网络中部署。

如果 SideStore 报错属于 Apple ID、Anisette、pairing file、App ID limit 等问题，需要先在 SideStore 本身排查。

## 核心文件说明

```text
cmd/xiaomi-router-autosign/main.go
```

用户态 TUN 程序，负责读取、改写、写回 IPv4 包。

```text
scripts/start.sh
```

OpenWrt 启动脚本，负责启动程序、设置路由、插入 iptables 规则。

```text
scripts/status.sh
```

状态检查脚本，用于确认进程、路由、FORWARD、NAT 规则是否正常。

```text
scripts/cleanup.sh
```

清理脚本，用于停止程序并删除相关临时规则。

```text
docs/xiaomi-openwrt-shellclash.md
```

小米 OpenWrt + ShellClash 环境下的部署说明。

```text
docs/troubleshooting.md
```

常见问题和排查路径。

## 安全与隐私说明

请不要公开上传以下内容：

```text
*.mobiledevicepairing
Apple ID / 密码 / 2FA 信息
完整 Clash / ShellClash 配置
代理节点、订阅链接、token
完整 SSH 日志
路由器公网 IP
真实设备名
```

文档中建议使用占位符：

```text
<IPHONE_IP>
<ROUTER_IP>
<br-lan>
XianShengXingGe
```

## 典型部署效果

部署成功后，检查状态应类似：

```text
/data/xiaomi-router-autosign -iface sidestore -target 10.7.0.1
10.7.0.1 dev sidestore
FORWARD: br-lan → sidestore
FORWARD: sidestore → br-lan
NAT PREROUTING: RETURN br-lan 10.7.0.1
```

当 iPhone 刷新 SideStore 时，FORWARD 计数会增长，说明流量已经经过路由器上的 TUN 处理流程。

## 免责声明

本项目需要 root 权限，并会修改路由器的路由表和防火墙规则。请仅在本人拥有和可控的网络环境中使用。

使用前建议先理解脚本内容，并准备好 SSH 访问方式，以便在网络异常时手动清理规则或重启路由器。

本项目仅用于学习、研究和改善个人设备在家庭局域网中的使用体验。
