package main

import (
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"
	"unsafe"
)

const (
	appVersion = "0.5.1-public"

	tunDevice  = "/dev/net/tun"
	tunSetIFF  = 0x400454ca
	iffTun     = 0x0001
	iffNoPI    = 0x1000
	ifNameSize = 16

	ethPAll         = 0x0003
	packetOutgoing  = 4
	defaultTarget   = "10.7.0.1"
	defaultTunnelIf = "sidestore"
	defaultBridgeIf = "br-lan"
)

type ifReq struct {
	Name  [ifNameSize]byte
	Flags uint16
	Pad   [22]byte
}

type commonConfig struct {
	target  net.IP
	verbose bool
}

type dhcpConfig struct {
	phoneMAC net.HardwareAddr
	target   net.IP
	router   net.IP
	gateway  net.IP
	bridge   string
}

func main() {
	mode := flag.String("mode", "reflector", "mode: reflector or dhcp121-injector")
	iface := flag.String("iface", defaultTunnelIf, "TUN interface name for reflector mode")
	target := flag.String("target", defaultTarget, "SideStore override peer IPv4 address to reflect")
	phoneMAC := flag.String("phone-mac", "", "iPhone Wi-Fi MAC for dhcp121-injector")
	routerIP := flag.String("router", "", "router/child-router LAN IPv4 used as the /32 next hop")
	gatewayIP := flag.String("gateway", "", "normal LAN default gateway to preserve in Option 121")
	bridge := flag.String("bridge", defaultBridgeIf, "bridge master name; used to avoid learning the bridge itself as phone-facing port")
	showVersion := flag.Bool("version", false, "print version and exit")
	verbose := flag.Bool("v", false, "verbose packet logging")
	flag.Parse()

	if *showVersion {
		fmt.Println(appVersion)
		return
	}

	targetIP := net.ParseIP(*target).To4()
	if targetIP == nil {
		log.Fatalf("invalid IPv4 target: %q", *target)
	}

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	switch *mode {
	case "reflector", "gateway": // gateway kept as a compatibility alias for older scripts.
		cfg := commonConfig{target: targetIP, verbose: *verbose}
		runReflector(*iface, cfg)
	case "dhcp121-injector":
		m, err := net.ParseMAC(*phoneMAC)
		if err != nil || len(m) != 6 {
			log.Fatalf("invalid -phone-mac %q", *phoneMAC)
		}
		router := net.ParseIP(*routerIP).To4()
		gateway := net.ParseIP(*gatewayIP).To4()
		if router == nil || gateway == nil {
			log.Fatalf("-router and -gateway must both be valid IPv4 addresses")
		}
		runDHCP121Injector(dhcpConfig{phoneMAC: m, target: targetIP, router: router, gateway: gateway, bridge: *bridge})
	default:
		log.Fatalf("unsupported mode %q; use reflector or dhcp121-injector", *mode)
	}
}

func runReflector(iface string, cfg commonConfig) {
	f, actualName, err := openTun(iface)
	if err != nil {
		log.Fatalf("open TUN failed: %v", err)
	}
	defer f.Close()
	log.Printf("xiaomi-router-7day-refresh %s reflector started: iface=%s target=%s", appVersion, actualName, cfg.target)

	installSignalExit(func() { _ = f.Close() })

	buf := make([]byte, 65535)
	var count uint64
	for {
		n, err := f.Read(buf)
		if err != nil {
			if errors.Is(err, os.ErrClosed) {
				return
			}
			log.Printf("TUN read error: %v", err)
			time.Sleep(time.Second)
			continue
		}
		if n == 0 {
			continue
		}
		pkt := buf[:n]
		info, ok := rewriteIPv4(pkt, cfg.target)
		if !ok {
			if cfg.verbose {
				log.Printf("ignored non-target packet len=%d", n)
			}
			continue
		}
		if _, err := f.Write(pkt); err != nil {
			log.Printf("TUN write error: %v", err)
			continue
		}
		count++
		if cfg.verbose || count <= 20 || count%1000 == 0 {
			log.Printf("reflector rewrote packet #%d: %s", count, info)
		}
	}
}

func runDHCP121Injector(c dhcpConfig) {
	fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(htons(ethPAll)))
	if err != nil {
		log.Fatalf("AF_PACKET socket: %v", err)
	}
	defer syscall.Close(fd)
	_ = syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_RCVBUF, 1<<20)

	log.Printf("xiaomi-router-7day-refresh %s DHCP121 injector started: phone=%s target=%s/32 via %s default-via=%s", appVersion, c.phoneMAC, c.target, c.router, c.gateway)
	log.Printf("waiting for iPhone DHCP request to learn phone-facing bridge member")

	installSignalExit(func() { _ = syscall.Close(fd) })

	buf := make([]byte, 65535)
	phoneIf := 0
	phoneIfName := ""
	patchedXID := map[uint32]time.Time{}

	for {
		n, sa, err := syscall.Recvfrom(fd, buf, 0)
		if err != nil {
			if err == syscall.EBADF || err == syscall.EINVAL {
				return
			}
			log.Printf("AF_PACKET receive error: %v", err)
			time.Sleep(100 * time.Millisecond)
			continue
		}
		sll, _ := sa.(*syscall.SockaddrLinklayer)
		if sll != nil && sll.Pkttype == packetOutgoing {
			continue
		}
		if n < 300 {
			continue
		}

		frame := append([]byte(nil), buf[:n]...)
		p, ok := parseDHCP(frame)
		if !ok {
			continue
		}

		// Client Request: learn the actual Wi-Fi bridge member used by this iPhone.
		if p.srcPort == 68 && p.dstPort == 67 && p.bootpOp == 1 && equalBytes(p.chaddr[:6], c.phoneMAC) {
			if sll != nil {
				name := interfaceName(sll.Ifindex)
				if name != "" && name != c.bridge && name != "lo" && phoneIf != sll.Ifindex {
					phoneIf = sll.Ifindex
					phoneIfName = name
					log.Printf("learned iPhone ingress interface: %s (ifindex=%d), xid=0x%08x", phoneIfName, phoneIf, p.xid)
				}
			}
			continue
		}

		// Only patch DHCP ACKs for the selected iPhone.
		if p.srcPort != 67 || p.dstPort != 68 || p.bootpOp != 2 || !equalBytes(p.chaddr[:6], c.phoneMAC) || p.msgType != 5 {
			continue
		}
		if phoneIf == 0 {
			log.Printf("saw DHCP ACK xid=0x%08x but phone-facing interface is not learned; reconnect Wi-Fi again", p.xid)
			continue
		}
		if t, exists := patchedXID[p.xid]; exists && time.Since(t) < 3*time.Second {
			continue
		}

		out, mergedExisting121, err := patchDHCP121(frame, p, c)
		if err != nil {
			log.Printf("patch DHCP ACK xid=0x%08x: %v", p.xid, err)
			continue
		}

		// Send a unicast L2 ACK directly back to the learned iPhone-facing Wi-Fi port.
		copy(out[0:6], c.phoneMAC)
		var addr [8]byte
		copy(addr[:6], c.phoneMAC)
		to := &syscall.SockaddrLinklayer{
			Protocol: htons(binary.BigEndian.Uint16(out[12:14])),
			Ifindex:  phoneIf,
			Halen:    6,
			Addr:     addr,
		}
		if err := syscall.Sendto(fd, out, 0, to); err != nil {
			log.Printf("send patched DHCP ACK on %s: %v", phoneIfName, err)
			continue
		}
		patchedXID[p.xid] = time.Now()
		if mergedExisting121 {
			log.Printf("INJECTED DHCP ACK xid=0x%08x on %s: prepended %s/32 via %s to existing Option121 (frame %d -> %d bytes)", p.xid, phoneIfName, c.target, c.router, len(frame), len(out))
		} else {
			log.Printf("INJECTED DHCP ACK xid=0x%08x on %s: Option121 %s/32 via %s + default via %s (frame %d -> %d bytes)", p.xid, phoneIfName, c.target, c.router, c.gateway, len(frame), len(out))
		}
	}
}

type dhcpPacket struct {
	ipOff, ihl, udpOff, bootpOff, optsOff int
	endOpt                                int
	option121Start                        int
	option121End                          int
	srcPort, dstPort                      uint16
	bootpOp                               byte
	xid                                   uint32
	chaddr                                [16]byte
	msgType                               byte
}

func parseDHCP(frame []byte) (dhcpPacket, bool) {
	var p dhcpPacket
	p.endOpt = -1
	p.option121Start = -1
	p.option121End = -1

	if len(frame) < 14 {
		return p, false
	}
	etherType := binary.BigEndian.Uint16(frame[12:14])
	ipOff := 14
	for etherType == 0x8100 || etherType == 0x88a8 {
		if len(frame) < ipOff+4 {
			return p, false
		}
		etherType = binary.BigEndian.Uint16(frame[ipOff+2 : ipOff+4])
		ipOff += 4
	}
	if etherType != 0x0800 || len(frame) < ipOff+20 || frame[ipOff]>>4 != 4 {
		return p, false
	}
	ihl := int(frame[ipOff]&0x0f) * 4
	if ihl < 20 || len(frame) < ipOff+ihl+8 || frame[ipOff+9] != 17 {
		return p, false
	}
	udpOff := ipOff + ihl
	sp := binary.BigEndian.Uint16(frame[udpOff : udpOff+2])
	dp := binary.BigEndian.Uint16(frame[udpOff+2 : udpOff+4])
	if !((sp == 67 && dp == 68) || (sp == 68 && dp == 67)) {
		return p, false
	}
	bootp := udpOff + 8
	if len(frame) < bootp+240 {
		return p, false
	}
	if !equalBytes(frame[bootp+236:bootp+240], []byte{0x63, 0x82, 0x53, 0x63}) {
		return p, false
	}

	p.ipOff = ipOff
	p.ihl = ihl
	p.udpOff = udpOff
	p.bootpOff = bootp
	p.optsOff = bootp + 240
	p.srcPort = sp
	p.dstPort = dp
	p.bootpOp = frame[bootp]
	p.xid = binary.BigEndian.Uint32(frame[bootp+4 : bootp+8])
	copy(p.chaddr[:], frame[bootp+28:bootp+44])

	for i := p.optsOff; i < len(frame); {
		code := frame[i]
		if code == 0 {
			i++
			continue
		}
		if code == 255 {
			p.endOpt = i
			break
		}
		if i+1 >= len(frame) {
			return p, false
		}
		length := int(frame[i+1])
		if i+2+length > len(frame) {
			return p, false
		}
		if code == 53 && length == 1 {
			p.msgType = frame[i+2]
		}
		if code == 121 && p.option121Start < 0 {
			p.option121Start = i
			p.option121End = i + 2 + length
		}
		i += 2 + length
	}
	if p.endOpt < 0 {
		return p, false
	}
	return p, true
}

func patchDHCP121(frame []byte, p dhcpPacket, c dhcpConfig) ([]byte, bool, error) {
	targetRoute := []byte{32, c.target[0], c.target[1], c.target[2], c.target[3], c.router[0], c.router[1], c.router[2], c.router[3]}
	mergedExisting := p.option121Start >= 0
	var data []byte
	insertAt := p.endOpt
	removeEnd := p.endOpt

	if mergedExisting {
		existingLen := int(frame[p.option121Start+1])
		existing := frame[p.option121Start+2 : p.option121Start+2+existingLen]
		if len(targetRoute)+len(existing) > 255 {
			return nil, true, fmt.Errorf("existing Option121 is too large to prepend the SideStore /32 route")
		}
		data = append(append([]byte{}, targetRoute...), existing...)
		insertAt = p.option121Start
		removeEnd = p.option121End
	} else {
		// RFC3442 clients ignore the legacy Router option when Option121 is present,
		// so preserve normal Internet routing by including a default route too.
		data = append(append([]byte{}, targetRoute...), 0, c.gateway[0], c.gateway[1], c.gateway[2], c.gateway[3])
	}

	opt := append([]byte{121, byte(len(data))}, data...)
	delta := len(opt) - (removeEnd - insertAt)
	out := make([]byte, len(frame)+delta)
	copy(out[:insertAt], frame[:insertAt])
	copy(out[insertAt:insertAt+len(opt)], opt)
	copy(out[insertAt+len(opt):], frame[removeEnd:])

	total := int(binary.BigEndian.Uint16(out[p.ipOff+2 : p.ipOff+4]))
	udpLen := int(binary.BigEndian.Uint16(out[p.udpOff+4 : p.udpOff+6]))
	if total <= 0 || udpLen <= 0 || total+delta > 65535 || udpLen+delta > 65535 {
		return nil, mergedExisting, fmt.Errorf("invalid IPv4/UDP lengths after patch")
	}
	binary.BigEndian.PutUint16(out[p.ipOff+2:p.ipOff+4], uint16(total+delta))
	binary.BigEndian.PutUint16(out[p.udpOff+4:p.udpOff+6], uint16(udpLen+delta))

	out[p.ipOff+10], out[p.ipOff+11] = 0, 0
	binary.BigEndian.PutUint16(out[p.ipOff+10:p.ipOff+12], checksum(out[p.ipOff:p.ipOff+p.ihl]))

	// IPv4 permits UDP checksum 0. Raw L2 injection with checksum offload is more
	// predictable when the injected DHCP packet explicitly uses checksum 0.
	out[p.udpOff+6], out[p.udpOff+7] = 0, 0
	return out, mergedExisting, nil
}

func rewriteIPv4(pkt []byte, target net.IP) (string, bool) {
	if len(pkt) < 20 || pkt[0]>>4 != 4 {
		return "", false
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl {
		return "", false
	}
	totalLen := int(binary.BigEndian.Uint16(pkt[2:4]))
	if totalLen < ihl || totalLen > len(pkt) {
		totalLen = len(pkt)
	}
	pkt = pkt[:totalLen]
	if !equalIPv4(pkt[16:20], target) {
		return "", false
	}

	oldSrc := net.IP(pkt[12:16]).String()
	oldDst := net.IP(pkt[16:20]).String()
	var tmp [4]byte
	copy(tmp[:], pkt[12:16])
	copy(pkt[12:16], pkt[16:20])
	copy(pkt[16:20], tmp[:])

	pkt[10], pkt[11] = 0, 0
	binary.BigEndian.PutUint16(pkt[10:12], checksum(pkt[:ihl]))

	proto := pkt[9]
	frag := binary.BigEndian.Uint16(pkt[6:8])
	fragOffset := frag & 0x1fff
	moreFrags := (frag & 0x2000) != 0
	if fragOffset == 0 && !moreFrags {
		switch proto {
		case 6:
			if totalLen-ihl >= 20 {
				pkt[ihl+16], pkt[ihl+17] = 0, 0
				binary.BigEndian.PutUint16(pkt[ihl+16:ihl+18], transportChecksum(pkt, ihl, proto))
			}
		case 17:
			if totalLen-ihl >= 8 {
				pkt[ihl+6], pkt[ihl+7] = 0, 0
				c := transportChecksum(pkt, ihl, proto)
				if c == 0 {
					c = 0xffff
				}
				binary.BigEndian.PutUint16(pkt[ihl+6:ihl+8], c)
			}
		}
	}
	return fmt.Sprintf("%s -> %s became %s -> %s proto=%d len=%d", oldSrc, oldDst, oldDst, oldSrc, proto, totalLen), true
}

func openTun(name string) (*os.File, string, error) {
	f, err := os.OpenFile(tunDevice, os.O_RDWR, 0)
	if err != nil {
		return nil, "", err
	}
	var req ifReq
	copy(req.Name[:], []byte(name))
	req.Flags = iffTun | iffNoPI
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(tunSetIFF), uintptr(unsafe.Pointer(&req)))
	if errno != 0 {
		_ = f.Close()
		return nil, "", errno
	}
	actual := string(req.Name[:])
	for i, b := range []byte(actual) {
		if b == 0 {
			actual = actual[:i]
			break
		}
	}
	return f, actual, nil
}

func installSignalExit(closeFn func()) {
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		s := <-sigCh
		log.Printf("received %s, exiting", s)
		closeFn()
	}()
}

func equalIPv4(b []byte, ip net.IP) bool {
	return len(b) >= 4 && len(ip) == 4 && b[0] == ip[0] && b[1] == ip[1] && b[2] == ip[2] && b[3] == ip[3]
}

func equalBytes(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func interfaceName(index int) string {
	i, err := net.InterfaceByIndex(index)
	if err != nil {
		return ""
	}
	return i.Name
}

func checksum(data []byte) uint16 {
	var sum uint32
	for len(data) >= 2 {
		sum += uint32(binary.BigEndian.Uint16(data[:2]))
		data = data[2:]
	}
	if len(data) == 1 {
		sum += uint32(data[0]) << 8
	}
	for sum>>16 != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	return ^uint16(sum)
}

func transportChecksum(pkt []byte, ihl int, proto byte) uint16 {
	length := len(pkt) - ihl
	pseudo := make([]byte, 0, 12+length+1)
	pseudo = append(pseudo, pkt[12:16]...)
	pseudo = append(pseudo, pkt[16:20]...)
	pseudo = append(pseudo, 0, proto, byte(length>>8), byte(length))
	pseudo = append(pseudo, pkt[ihl:]...)
	if len(pseudo)%2 == 1 {
		pseudo = append(pseudo, 0)
	}
	return checksum(pseudo)
}

func htons(v uint16) uint16 { return (v<<8)&0xff00 | v>>8 }
