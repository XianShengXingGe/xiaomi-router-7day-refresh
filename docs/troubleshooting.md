# Troubleshooting / 排查问题

## 中文

### 检查路由器能力

先确认路由器具备运行本项目的基础能力：

```sh
uname -m
ls -l /dev/net/tun 2>/dev/null
cat /dev/net/tun 2>&1 | head -5
which iptables
which nft
```

如果 `/dev/net/tun` 可用，下面这个命令通常会返回类似结果：

```text
cat: read error: File descriptor in bad state
```

这通常表示 TUN 设备存在并且可以被程序打开。

### 检查运行状态

优先使用友好的状态检查脚本：

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

关键结果应类似：

```text
[OK] helper process is running
[OK] TUN interface sidestore is up
[OK] route to 10.7.0.1 uses sidestore
```

如果需要更底层的检查，可以运行：

```sh
ps | grep xiaomi-router-7day-refresh
ip route get 10.7.0.1
iptables -L FORWARD -n -v --line-numbers | head -12
iptables -t nat -L PREROUTING -n -v --line-numbers | head -12
cat /tmp/xiaomi-router-7day-refresh.log
```

### `wget: not an http or ftp url`

部分旧版 BusyBox `wget` 不支持 HTTPS，因此会拒绝 GitHub 的 `https://` 下载地址。请使用项目文档中的 `curl` 安装命令，而不是直接使用 `wget`：

```sh
cd /tmp
rm -f install.sh
curl -fLk -o install.sh \
  'https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh'
sh install.sh
```

安装器后续下载二进制和辅助脚本时也会优先使用 `curl`。

### `curl: (22) The requested URL returned error: 404`

这表示 GitHub 没有在该下载地址提供对应文件。请依次检查：

1. 仓库是否已经发布正式 GitHub Release。
2. Release 是否仍是 Draft，或是否只有 prerelease。
3. 正式 Release Assets 中是否存在 `install.sh`。
4. Asset 文件名是否与下载地址中的 `install.sh` 完全一致。
5. GitHub Actions 的发布任务是否失败。

`releases/latest/download/...` 仅指向最新的正式 Release；Draft 和 prerelease 不应作为普通用户的安装来源。

### `open TUN failed: device or resource busy`

这通常表示之前的进程还占用着 TUN 接口。

可以先停止旧进程并删除旧接口：

```sh
for PID in $(ps | grep '[x]iaomi-router-7day-refresh' | awk '{print $1}'); do
  kill -9 "$PID" 2>/dev/null
done
ip link del sidestore 2>/dev/null
```

然后重新启动：

```sh
/data/xiaomi-router-7day-refresh-start.sh
```

### iPhone IP 发生变化

本项目的防火墙规则会绑定到 iPhone 的固定局域网 IP。如果 iPhone IP 变化，请先在小米路由器后台的 DHCP 静态 IP 分配页面重新固定 IP，然后更新配置文件中的 `IPHONE`：

```text
/data/xiaomi-router-7day-refresh.conf
```

修改后重启：

```sh
/data/xiaomi-router-7day-refresh-start.sh
```

### SideStore 仍提示 LocalDevVPN 或 pairing 问题

路由器侧包改写可能已经正常工作。请先观察状态脚本和 FORWARD 计数是否增长，然后在 iPhone 上检查：

1. SideStore 是否拥有本地网络权限。
2. 是否没有启用其他 VPN。
3. pairing file 是否有效，并且由预期的 iLoader / SideStore 流程生成。
4. 替换 pairing file 后，是否已经杀掉并重新打开 SideStore。

### ShellClash 规则顺序

如果重启后 NAT `RETURN` 规则不在 ShellClash 规则之前，请确认启动脚本仍然等待 ShellClash 初始化完成后再插入规则：

```sh
grep '^sleep 60' /data/xiaomi-router-7day-refresh-start.sh
```

## English

### Check router capability

First, make sure the router has the basic capabilities required by this project:

```sh
uname -m
ls -l /dev/net/tun 2>/dev/null
cat /dev/net/tun 2>&1 | head -5
which iptables
which nft
```

If `/dev/net/tun` is usable, this command usually returns something like:

```text
cat: read error: File descriptor in bad state
```

This usually means the TUN device exists and can be opened by the helper.

### Check running status

Start with the friendly status command:

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

Expected key results:

```text
[OK] helper process is running
[OK] TUN interface sidestore is up
[OK] route to 10.7.0.1 uses sidestore
```

For lower-level checks, run:

```sh
ps | grep xiaomi-router-7day-refresh
ip route get 10.7.0.1
iptables -L FORWARD -n -v --line-numbers | head -12
iptables -t nat -L PREROUTING -n -v --line-numbers | head -12
cat /tmp/xiaomi-router-7day-refresh.log
```

### `wget: not an http or ftp url`

Some older BusyBox `wget` builds do not support HTTPS, so they reject GitHub `https://` download URLs. Use the documented `curl` installation command instead of invoking `wget` directly:

```sh
cd /tmp
rm -f install.sh
curl -fLk -o install.sh \
  'https://github.com/XianShengXingGe/xiaomi-router-7day-refresh/releases/latest/download/install.sh'
sh install.sh
```

The installer also prefers `curl` for its later binary and helper-script downloads.

### `curl: (22) The requested URL returned error: 404`

This means GitHub does not provide a file at that download URL. Check the following:

1. A published GitHub Release exists.
2. The Release is not still a Draft and the repository does not have only prereleases.
3. The published Release Assets include `install.sh`.
4. The asset name exactly matches `install.sh` in the download URL.
5. The GitHub Actions publishing job succeeded.

`releases/latest/download/...` resolves only to the newest published, non-prerelease Release; Drafts and prereleases are not normal user installation sources.

### `open TUN failed: device or resource busy`

This usually means a previous process is still holding the TUN interface.

Stop old processes and remove the old interface:

```sh
for PID in $(ps | grep '[x]iaomi-router-7day-refresh' | awk '{print $1}'); do
  kill -9 "$PID" 2>/dev/null
done
ip link del sidestore 2>/dev/null
```

Then restart:

```sh
/data/xiaomi-router-7day-refresh-start.sh
```

### iPhone IP changed

The firewall rules are bound to the iPhone fixed LAN IP. If the iPhone IP changes, first fix it again in the Xiaomi router's DHCP static IP assignment page, then update `IPHONE` in:

```text
/data/xiaomi-router-7day-refresh.conf
```

After editing, restart:

```sh
/data/xiaomi-router-7day-refresh-start.sh
```

### SideStore still reports LocalDevVPN or pairing issues

Router-side packet rewriting may already be working. Check whether the status script looks healthy and whether FORWARD counters increase. Then verify on the iPhone:

1. SideStore has Local Network permission.
2. No other VPN is active.
3. The pairing file is valid and generated by the expected iLoader / SideStore flow.
4. SideStore has been killed and reopened after replacing the pairing file.

### ShellClash rule order

If the NAT `RETURN` rule is not before ShellClash rules after reboot, make sure the startup script still waits for ShellClash before inserting rules:

```sh
grep '^sleep 60' /data/xiaomi-router-7day-refresh-start.sh
```
