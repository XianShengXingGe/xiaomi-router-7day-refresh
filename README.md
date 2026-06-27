# Xiaomi Router Auto-Sign for SideStore / LiveContainer

Run a lightweight router-side helper on a Xiaomi/OpenWrt router so SideStore or LiveContainer can refresh apps automatically when an iPhone joins your home Wi-Fi.

The intended setup is:

1. Enable SSH on the Xiaomi router.
2. SSH into the router from Windows, macOS, or Linux.
3. Run the interactive installer inside the router shell.
4. Keep the iPhone on a fixed LAN IP.
5. Use iOS Shortcuts automation to trigger SideStore / LiveContainer refresh after connecting to this Wi-Fi.

This project was tested on a Xiaomi router with OpenWrt 18.06 based firmware and ShellClash installed. Other OpenWrt routers may work if they provide `/dev/net/tun`, `ip`, and `iptables`.

## Quick Start

### 1. Prepare the iPhone and router

Before installing, make the iPhone IP stable:

1. On the iPhone, open the current Wi-Fi network settings and set **Private Wi-Fi Address** to **Fixed** or **Off**.
2. In the Xiaomi router admin page, enable and use **DHCP static IP assignment** to bind this iPhone to a fixed LAN IP.

Write down that fixed iPhone IP, for example `192.168.31.100`.

### 2. SSH into the router

Open Terminal, Windows Terminal, or PowerShell on your computer, then SSH into the router.

This address is only an example:

```sh
ssh root@192.168.31.1
```

Your router address may be different. Use the actual LAN IP of your router.

### 3. Run the installer on the router

After you are inside the router shell, run:

```sh
cd /tmp
wget https://github.com/XianShengXingGe/xiaomi-router-autosign/releases/latest/download/install.sh
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
/data/xiaomi-router-autosign
/data/xiaomi-router-autosign.conf
/data/xiaomi-router-autosign-start.sh
/data/xiaomi-router-autosign-status.sh
/data/xiaomi-router-autosign-cleanup.sh
```

### 4. Check status

```sh
/data/xiaomi-router-autosign-status.sh
```

Expected key results:

```text
[OK] helper process is running
[OK] TUN interface sidestore exists
[OK] TUN interface sidestore is up
[OK] route to 10.7.0.1 uses sidestore
```

### 5. Add iOS Shortcuts automation

After router-side setup is working, create an iOS Shortcuts automation:

1. Trigger: when the iPhone joins your home Wi-Fi.
2. Action: open SideStore or LiveContainer.
3. Optional action: run the refresh shortcut or URL scheme you already use for your setup.

The router helper only handles the network path. The actual refresh still depends on SideStore / LiveContainer, a valid pairing file, local network permission, and a healthy Apple ID / Anisette state.

## What It Does

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

## Status

Experimental. Tested in one real Xiaomi/OpenWrt/ShellClash environment.

This project does not:

- replace SideStore or LiveContainer
- bypass Apple ID, signing, certificate, or App ID limits
- generate or replace pairing files
- fix Anisette or Apple service errors
- guarantee compatibility with every iOS, SideStore, LiveContainer, or OpenWrt version

## Tested Environment

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

## Security Notes

This tool requires root access on the router and changes routing/firewall behavior. Use it only on networks you control.

Do not publish or upload:

- Apple ID credentials
- SideStore / LiveContainer pairing files (`*.mobiledevicepairing`)
- Clash/ShellClash subscription config
- proxy nodes or tokens
- full terminal logs containing personal device information
- public router IPs or real device names

## Manual Build

```bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dist/xiaomi-router-autosign-linux-arm64 ./cmd/xiaomi-router-autosign
```

Or:

```bash
make build-arm64
```

## Manual Commands

Start:

```sh
/data/xiaomi-router-autosign-start.sh
```

Stop and clean rules:

```sh
/data/xiaomi-router-autosign-cleanup.sh
```

Status:

```sh
/data/xiaomi-router-autosign-status.sh
```

## Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md).

## Credits

Inspired by:

- SideStore / LocalDevVPN behavior
- StosVPN
- xddxdd/sidestore-vpn
- Lantian's write-up on using SideStore without StosVPN across LAN

This project is not affiliated with SideStore, LiveContainer, StosVPN, xddxdd, or Lantian.

## License

MIT
