//go:build linux

package main

import (
	"encoding/binary"
	"log"
	"os"
	"syscall"
	"time"
	"unsafe"
)

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

func runDHCP121Injector(c dhcpConfig) {
	fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(htons(ethPAll)))
	if err != nil {
		log.Fatalf("AF_PACKET socket: %v", err)
	}
	defer syscall.Close(fd)
	_ = syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_RCVBUF, 1<<20)

	log.Printf("xiaomi-router-7day-refresh %s DHCP121 injector started: phone=%s target=%s/32 via %s default-via=%s", appVersion, maskMAC(c.phoneMAC), c.target, c.router, c.gateway)
	log.Printf("waiting for iPhone DHCP request to learn phone-facing bridge member")

	installSignalExit(func() { _ = syscall.Close(fd) })

	buf := make([]byte, 65535)
	phoneIf := 0
	phoneIfName := ""
	var ring xidRing

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

		// Fast pre-filter directly on buf: drop non-DHCP frames without heap allocations.
		if !isQuickDHCPCandidate(buf[:n]) {
			continue
		}

		p, ok := parseDHCP(buf[:n])
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
		if ring.recentlySeen(p.xid, 3*time.Second) {
			continue
		}

		out, mergedExisting121, err := patchDHCP121(buf[:n], p, c)
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
		ring.record(p.xid)
		if mergedExisting121 {
			log.Printf("INJECTED DHCP ACK xid=0x%08x on %s: prepended %s/32 via %s to existing Option121 (frame %d -> %d bytes)", p.xid, phoneIfName, c.target, c.router, n, len(out))
		} else {
			log.Printf("INJECTED DHCP ACK xid=0x%08x on %s: Option121 %s/32 via %s + default via %s (frame %d -> %d bytes)", p.xid, phoneIfName, c.target, c.router, c.gateway, n, len(out))
		}
	}
}
