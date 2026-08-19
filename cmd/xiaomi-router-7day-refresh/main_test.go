package main

import (
	"encoding/binary"
	"net"
	"testing"
	"time"
)

func TestRewriteIPv4Reflector(t *testing.T) {
	pkt := makeTCPPacket(t, net.IPv4(192, 0, 2, 100), net.IPv4(10, 7, 0, 1), 50797, 12345)
	ok := rewriteIPv4(pkt, net.IPv4(10, 7, 0, 1).To4())
	if !ok {
		t.Fatalf("rewrite failed")
	}
	if got := net.IP(pkt[12:16]).String(); got != "10.7.0.1" {
		t.Fatalf("src ip=%s", got)
	}
	if got := net.IP(pkt[16:20]).String(); got != "192.0.2.100" {
		t.Fatalf("dst ip=%s", got)
	}
	if checksum(pkt[:20]) != 0 {
		t.Fatalf("bad IPv4 checksum")
	}
	if transportChecksum(pkt, 20, 6) != 0 {
		t.Fatalf("bad TCP checksum")
	}
}

func TestQuickDHCPCandidateFilter(t *testing.T) {
	dhcpAck := makeDHCPAck(t, false)
	if !isQuickDHCPCandidate(dhcpAck) {
		t.Fatalf("expected valid DHCP frame to pass candidate filter")
	}

	nonDHCP := append([]byte(nil), dhcpAck...)
	// Change UDP dst port from 68 to 80 (HTTP)
	nonDHCP[36], nonDHCP[37] = 0, 80
	if isQuickDHCPCandidate(nonDHCP) {
		t.Fatalf("expected non-DHCP UDP port 80 to be filtered out")
	}

	nonIP := append([]byte(nil), dhcpAck...)
	// Change EtherType to ARP (0x0806)
	nonIP[12], nonIP[13] = 0x08, 0x06
	if isQuickDHCPCandidate(nonIP) {
		t.Fatalf("expected ARP packet to be filtered out")
	}
}

func TestXIDRing(t *testing.T) {
	var ring xidRing
	if ring.recentlySeen(0x12345678, time.Second) {
		t.Fatalf("empty ring should not match xid")
	}
	ring.record(0x12345678)
	if !ring.recentlySeen(0x12345678, time.Second) {
		t.Fatalf("recorded xid should be recently seen")
	}
	if ring.recentlySeen(0x99999999, time.Second) {
		t.Fatalf("unrecorded xid should not be seen")
	}
}

func TestPatchDHCP121AddsHostAndDefault(t *testing.T) {
	frame := makeDHCPAck(t, false)
	p, ok := parseDHCP(frame)
	if !ok || p.msgType != 5 || p.option121Start >= 0 {
		t.Fatalf("failed to parse base ACK")
	}
	mac, _ := net.ParseMAC("02:11:22:33:44:55")
	out, merged, err := patchDHCP121(frame, p, dhcpConfig{
		phoneMAC: mac,
		target:   net.IPv4(10, 7, 0, 1).To4(),
		router:   net.IPv4(192, 0, 2, 2).To4(),
		gateway:  net.IPv4(192, 0, 2, 1).To4(),
	})
	if err != nil || merged {
		t.Fatalf("patch failed merged=%v err=%v", merged, err)
	}
	p2, ok := parseDHCP(out)
	if !ok || p2.option121Start < 0 {
		t.Fatalf("patched ACK has no option121")
	}
	data := optionData(out, p2.option121Start)
	want := []byte{32, 10, 7, 0, 1, 192, 0, 2, 2, 0, 192, 0, 2, 1}
	if !equalBytes(data, want) {
		t.Fatalf("option121=%v want=%v", data, want)
	}
}

func TestPatchDHCP121PreservesExistingRoutes(t *testing.T) {
	frame := makeDHCPAck(t, true)
	p, ok := parseDHCP(frame)
	if !ok || p.option121Start < 0 {
		t.Fatalf("expected existing option121")
	}
	old := append([]byte(nil), optionData(frame, p.option121Start)...)
	mac, _ := net.ParseMAC("02:11:22:33:44:55")
	out, merged, err := patchDHCP121(frame, p, dhcpConfig{
		phoneMAC: mac,
		target:   net.IPv4(10, 7, 0, 1).To4(),
		router:   net.IPv4(192, 0, 2, 2).To4(),
		gateway:  net.IPv4(192, 0, 2, 1).To4(),
	})
	if err != nil || !merged {
		t.Fatalf("merge failed merged=%v err=%v", merged, err)
	}
	p2, ok := parseDHCP(out)
	if !ok || p2.option121Start < 0 {
		t.Fatalf("patched ACK has no option121")
	}
	data := optionData(out, p2.option121Start)
	prefix := []byte{32, 10, 7, 0, 1, 192, 0, 2, 2}
	if len(data) != len(prefix)+len(old) || !equalBytes(data[:len(prefix)], prefix) || !equalBytes(data[len(prefix):], old) {
		t.Fatalf("existing routes not preserved: got=%v old=%v", data, old)
	}
}

func optionData(frame []byte, start int) []byte {
	l := int(frame[start+1])
	return frame[start+2 : start+2+l]
}

func makeTCPPacket(t *testing.T, srcIP, dstIP net.IP, srcPort, dstPort uint16) []byte {
	t.Helper()
	pkt := make([]byte, 40)
	pkt[0] = 0x45
	binary.BigEndian.PutUint16(pkt[2:4], uint16(len(pkt)))
	pkt[6] = 0x40
	pkt[8] = 64
	pkt[9] = 6
	copy(pkt[12:16], srcIP.To4())
	copy(pkt[16:20], dstIP.To4())
	binary.BigEndian.PutUint16(pkt[10:12], checksum(pkt[:20]))
	tcp := pkt[20:]
	binary.BigEndian.PutUint16(tcp[0:2], srcPort)
	binary.BigEndian.PutUint16(tcp[2:4], dstPort)
	binary.BigEndian.PutUint32(tcp[4:8], 0x12345678)
	tcp[12] = 5 << 4
	tcp[13] = 0x02
	binary.BigEndian.PutUint16(tcp[14:16], 65535)
	binary.BigEndian.PutUint16(tcp[16:18], transportChecksum(pkt, 20, 6))
	return pkt
}

func makeDHCPAck(t *testing.T, with121 bool) []byte {
	t.Helper()
	// Ethernet 14 + IPv4 20 + UDP 8 + BOOTP 240 + DHCP options + padding.
	options := []byte{53, 1, 5, 54, 4, 192, 0, 2, 1}
	if with121 {
		// Preserve an example 10.0.0.0/8 route via RFC 5737 documentation gateway 192.0.2.1.
		options = append(options, 121, 6, 8, 10, 192, 0, 2, 1)
	}
	options = append(options, 255)
	payloadLen := 240 + len(options) + 8
	frame := make([]byte, 14+20+8+payloadLen)
	copy(frame[0:6], []byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff})
	copy(frame[6:12], []byte{0x02, 0xaa, 0xbb, 0xcc, 0xdd, 0xee})
	binary.BigEndian.PutUint16(frame[12:14], 0x0800)
	ip := frame[14:]
	ip[0] = 0x45
	binary.BigEndian.PutUint16(ip[2:4], uint16(20+8+payloadLen))
	ip[8] = 64
	ip[9] = 17
	copy(ip[12:16], []byte{192, 0, 2, 1})
	copy(ip[16:20], []byte{255, 255, 255, 255})
	binary.BigEndian.PutUint16(ip[10:12], checksum(ip[:20]))
	udp := ip[20:]
	binary.BigEndian.PutUint16(udp[0:2], 67)
	binary.BigEndian.PutUint16(udp[2:4], 68)
	binary.BigEndian.PutUint16(udp[4:6], uint16(8+payloadLen))
	bootp := udp[8:]
	bootp[0] = 2
	binary.BigEndian.PutUint32(bootp[4:8], 0xf6c0b5d6)
	copy(bootp[28:34], []byte{0x02, 0x11, 0x22, 0x33, 0x44, 0x55})
	copy(bootp[236:240], []byte{0x63, 0x82, 0x53, 0x63})
	copy(bootp[240:], options)
	return frame
}
