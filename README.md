# 🚀 Xiaomi Router 7-Day Refresh for SideStore / LiveContainer
> 小米 / OpenWrt 路由器端 SideStore 7 天免电脑无感自动续签辅助工具  
> Effortless 7-Day SideStore / LiveContainer refresh helper on Xiaomi & OpenWrt routers.

[中文使用指南](#-中文使用指南) | [English Guide](#-english-guide)

---

## 📖 中文使用指南

### 💡 这是什么？解决了什么问题？

如果你在 iPhone 上使用 **SideStore** 或 **LiveContainer**（免越狱安装 IPA、微信多开、游戏模拟器等），苹果规定个人免费证书每 **7 天**必须刷新一次签名，否则应用会闪退打不开。

传统刷新方式的痛点：
- ❌ **依赖电脑**：每周都要打开电脑插线或连局域网，极其麻烦；
- ❌ **依赖手机端 VPN / 代理 App**：需要在 iPhone 上安装配置 Loon、Surge 等付费代理软件，或者开启手机自带 VPN 经常报错 `DeviceEndpoint 未初始化`、连接超时。

🎉 **本项目带来的改变：**
把所有繁琐的网络通信逻辑直接搬到家里的**小米 / OpenWrt 路由器**上！
- ✨ **手机零负担**：iPhone 不需要安装任何代理 App，也不用常驻 VPN。
- ✨ **连上 Wi-Fi 自动刷**：回家连上 Wi-Fi，打开 SideStore 点击 **Refresh** 即可秒级续签成功；更可以在 iOS **「快捷指令」** 中配置自动化，实现**连上 Wi-Fi 自动后台静默续签**！
- ✨ **全家上网不受影响**：只对你指定的这台 iPhone 生效，且只处理签名刷新流量，完全不影响正常刷视频、玩游戏。
- ✨ **支持无线中继/子路由**：即使你的小米路由只是挂在光猫或主路由下面的副路由，也能完美支持！

---

### 🛠️ 准备工作

1. **一台小米或 OpenWrt 路由器**：已开启 SSH 登录权限（[参考小米路由器开启 SSH 教程](https://jwsc.eu.org/gDyfIPSsZ/)）。
2. **获取 iPhone 的 Wi-Fi MAC 地址**：
   - 打开 iPhone **「设置」 -> 「无线局域网 (Wi-Fi)」**；
   - 点击当前连接的 Wi-Fi 名字右侧的 **蓝色 `(i)` 图标**；
   - 找到 **「私有无线局域网地址」**（例如 `AA:BB:CC:DD:EE:FF`），复制或记下来。

---

### 🚀 超简单安装步骤（只需 3 步）

用电脑或手机终端 SSH 登录你的路由器后台（例如 `ssh root@192.168.31.1`），然后复制粘贴以下命令回车：

```sh
cd /tmp && rm -f install.sh && (curl -fLk --connect-timeout 4 -o install.sh 'https://cdn.jsdelivr.net/gh/XianShengXingGe/xiaomi-router-7day-refresh@main/scripts/install.sh' || curl -fLk --connect-timeout 4 -o install.sh 'https://ghfast.top/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh' || curl -fLk --connect-timeout 4 -o install.sh 'https://ghproxy.net/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh') && sh install.sh
```
*(命令内置 jsDelivr 全球 CDN 与多线路国内镜像自动竞速回退，国内网络秒级下载)*

#### 终端安装引导（极简 3 步）：

1. **选择拓扑模式**：
   - 如果家里只有这一台小米路由器，输入 `1`（主路由模式）；
   - 如果这台小米路由器是插在光猫或其他主路由下面的（或者无线中继），直接按回车 `2`（无线中继模式，**最推荐**）。
2. **输入 iPhone MAC 地址**：
   - 粘贴你在准备工作中查到的 iPhone Wi-Fi MAC 地址，按回车。
3. **确认安装**：
   - 屏幕会显示自动探测到的路由器 IP 和网关，**直接按 [回车] 即可一键完成安装并启动**！

---

### 📱 首次激活与日常使用

1. **首次激活（重要）**：
   - 安装完成后，在 iPhone 上 **关闭 Wi-Fi -> 等待 2~3 秒 -> 重新打开 Wi-Fi 连接**（让手机重新获取路由器下发的刷新路由）。
2. **手动刷新测试**：
   - 打开 iPhone 上的 **SideStore**，点击 **Refresh All**；
   - 此时你会发现签名进度条飞速跑完，刷新成功！🎉
3. **日常使用与自动后台刷新（强烈推荐）**：
   - **手动**：连着家里 Wi-Fi 时，随时打开 SideStore 即可一键刷新。
   - **完全无感自动刷新**：打开 iOS 自带的 **「快捷指令」App -> 「自动化」 -> 「新建个人自动化」 -> 选择「加入无线局域网」**（选择家里的 Wi-Fi，勾选「立即运行」并关闭「运行时通知」）-> 添加操作 **SideStore 的「Refresh Apps」**。这样每次回家连上 Wi-Fi，iPhone 就会在后台完全自动静默续签，彻底告别 7 天过期烦恼！

---

### 📋 常用管理命令

在路由器 SSH 中随时可执行以下快捷命令：

- **查看运行状态与反射数据统计**：
  ```sh
  /data/xiaomi-router-7day-refresh-status.sh
  ```
- **一键在线升级到最新版本**：
  ```sh
  cd /tmp && rm -f upgrade.sh && (curl -fLk --connect-timeout 4 -o upgrade.sh 'https://cdn.jsdelivr.net/gh/XianShengXingGe/xiaomi-router-7day-refresh@main/scripts/upgrade.sh' || curl -fLk --connect-timeout 4 -o upgrade.sh 'https://ghfast.top/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/upgrade.sh' || curl -fLk --connect-timeout 4 -o upgrade.sh 'https://ghproxy.net/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/upgrade.sh') && sh upgrade.sh
  ```
- **排错诊断与抓包**：
  ```sh
  /data/xiaomi-router-7day-refresh-diagnose.sh
  ```
- **完全卸载与清理服务**：
  ```sh
  /data/xiaomi-router-7day-refresh-cleanup.sh
  ```

---

### 💖 鸣谢与参考 (Credits & References)

特别感谢以下开源项目与社区资料为本项目带来的灵感与技术基石：

- **[SideStore](https://sidestore.io/)** 与 **[LiveContainer](https://github.com/LiveContainer/LiveContainer)**：伟大的 iOS 免越狱应用侧载与签名方案。
- **StosVPN / LocalDevVPN** 以及 **[xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn)**：为 SideStore 设备回环通信机制提供的技术探索参考。
- **[OpenWrt](https://openwrt.org/)**、**dnsmasq** 与 **Linux TUN / iptables**：提供强大的底层路由、DHCP 注入与网络包处理能力。
- **[Juewuy 的小米路由器 SSH 教程](https://jwsc.eu.org/gDyfIPSsZ/)**：为小米路由器开启 SSH 提供的优秀教程指引。

---

<br/>

## 🌐 English Guide

### 💡 What is this? What problem does it solve?

When using **SideStore** or **LiveContainer** on iOS (for sideloading IPAs without jailbreaking), Apple requires free developer certificates to be refreshed every **7 days**, otherwise apps will fail to launch.

Traditional refresh methods:
- ❌ **Require a PC/Mac**: Connecting over USB or local network every week is tedious.
- ❌ **Require VPN / Proxy apps on iPhone**: Configuring third-party proxies (like Loon/Surge) or iPhone-side VPNs often suffers from timeouts or uninitialized device endpoint errors.

🎉 **What this project does:**
It moves all the network loopback handling directly to your home **Xiaomi / OpenWrt router**!
- ✨ **Zero iPhone modification**: No need for proxy apps or persistent VPN tunnels on your phone.
- ✨ **Refresh over home Wi-Fi & Automate**: Just connect to Wi-Fi and tap **Refresh** in SideStore; you can even configure iOS **Shortcuts Automation** to refresh apps completely automatically in the background whenever you connect to your home Wi-Fi!
- ✨ **Completely isolated**: Only affects the specified iPhone and SideStore refresh traffic (`10.7.0.1/32`), without affecting normal internet usage for other devices.
- ✨ **Supports wireless repeater / AP mode**: Works seamlessly even if your Xiaomi router is a child/secondary router behind an ISP modem.

---

### 🛠️ Preparation

1. **A Xiaomi or OpenWrt router** with root SSH access ([Xiaomi SSH Guide](https://jwsc.eu.org/gDyfIPSsZ/)).
2. **Find your iPhone's Wi-Fi MAC Address**:
   - On your iPhone, go to **Settings -> Wi-Fi**.
   - Tap the blue **`(i)` icon** next to your connected Wi-Fi name.
   - Copy the **Private Wi-Fi Address** (e.g. `AA:BB:CC:DD:EE:FF`).

---

### 🚀 Quick 3-Step Installation

Log in to your router via SSH (e.g., `ssh root@192.168.31.1`) and run:

```sh
cd /tmp && rm -f install.sh && (curl -fLk --connect-timeout 4 -o install.sh 'https://cdn.jsdelivr.net/gh/XianShengXingGe/xiaomi-router-7day-refresh@main/scripts/install.sh' || curl -fLk --connect-timeout 4 -o install.sh 'https://ghfast.top/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh' || curl -fLk --connect-timeout 4 -o install.sh 'https://ghproxy.net/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh') && sh install.sh
```

#### Simple Interactive Steps:

1. **Choose Topology**:
   - `1` for Main Router (if this is your only router).
   - `2` for Wireless Repeater / Child Router (Recommended, if connected behind another upstream router/modem).
2. **Enter iPhone Wi-Fi MAC**:
   - Paste your iPhone's Private Wi-Fi MAC address and hit Enter.
3. **Confirm and Install**:
   - Review the auto-detected settings and **press [Enter]** to complete installation and start the service!

---

### 📱 Activation and Usage

1. **Initial Activation**:
   - Turn iPhone **Wi-Fi OFF -> Wait 2 seconds -> Turn Wi-Fi ON** to receive the new DHCP route.
2. **Manual Refresh Test**:
   - Open **SideStore** and tap **Refresh All**. The apps will refresh instantly!
3. **Daily Routine & Background Automation (Highly Recommended)**:
   - **Manual**: Whenever you are home connected to Wi-Fi, open SideStore to refresh anytime.
   - **Seamless Background Automation**: Open the iOS **Shortcuts** app -> **Automation** -> **New Automation** -> Select **"Wi-Fi"** (choose your Home Wi-Fi, select "Run Immediately", disable "Notify When Run") -> Add action **SideStore: "Refresh Apps"**. Your iPhone will now refresh all sideloaded apps silently in the background whenever you return home!

---

### 📋 Useful Commands

- **Check Service & Traffic Status**:
  ```sh
  /data/xiaomi-router-7day-refresh-status.sh
  ```
- **One-click Upgrade**:
  ```sh
  cd /tmp && rm -f upgrade.sh && (curl -fLk --connect-timeout 4 -o upgrade.sh 'https://cdn.jsdelivr.net/gh/XianShengXingGe/xiaomi-router-7day-refresh@main/scripts/upgrade.sh' || curl -fLk --connect-timeout 4 -o upgrade.sh 'https://ghfast.top/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/upgrade.sh' || curl -fLk --connect-timeout 4 -o upgrade.sh 'https://ghproxy.net/https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/upgrade.sh') && sh upgrade.sh
  ```
- **Diagnostics & Packet Inspection**:
  ```sh
  /data/xiaomi-router-7day-refresh-diagnose.sh
  ```
- **Stop and Uninstall**:
  ```sh
  /data/xiaomi-router-7day-refresh-cleanup.sh
  ```

---

### 💖 Credits & References

Special thanks to the following open-source projects and communities:

- **[SideStore](https://sidestore.io/)** & **[LiveContainer](https://github.com/LiveContainer/LiveContainer)**: Revolutionary iOS sideloading and app refresh platforms.
- **StosVPN / LocalDevVPN** & **[xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn)**: Foundational insights into SideStore device loopback communication.
- **[OpenWrt](https://openwrt.org/)**, **dnsmasq**, and **Linux TUN / iptables**: Powerful routing, DHCP injection, and packet handling capabilities.
- **[Juewuy's Xiaomi Router SSH Guide](https://jwsc.eu.org/gDyfIPSsZ/)**: Excellent reference for unlocking SSH on Xiaomi routers.

---

### 📄 License

This project is licensed under the [MIT License](LICENSE).

