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
	tunDevice  = "/dev/net/tun"
	tunSetIFF  = 0x400454ca
	iffTun     = 0x0001
	iffNoPI    = 0x1000
	ifNameSize = 16
)

type ifReq struct {
	Name  [ifNameSize]byte
	Flags uint16
	Pad   [22]byte
}

type config struct {
	iface   string
	target  net.IP
	verbose bool
}

func main() {
	var cfg config
	iface := flag.String("iface", "sidestore", "TUN interface name")
	target := flag.String("target", "10.7.0.1", "IPv4 target address used by SideStore LocalDevVPN")
	verbose := flag.Bool("v", false, "enable verbose per-packet logging; avoid this for long-running router use")
	flag.Parse()

	cfg.iface = *iface
	cfg.verbose = *verbose
	cfg.target = net.ParseIP(*target).To4()
	if cfg.target == nil {
		log.Fatalf("invalid IPv4 target: %s", *target)
	}

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	log.Printf("xiaomi-router-autosign starting: iface=%s target=%s", cfg.iface, cfg.target.String())

	f, actualName, err := openTun(cfg.iface)
	if err != nil {
		log.Fatalf("open TUN failed: %v", err)
	}
	defer f.Close()
	log.Printf("TUN device %q opened", actualName)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		s := <-sigCh
		log.Printf("received %s, exiting", s)
		os.Exit(0)
	}()

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
				log.Printf("ignored non-IPv4/unsupported packet len=%d", n)
			}
			continue
		}
		if _, err := f.Write(pkt); err != nil {
			log.Printf("TUN write error: %v", err)
			continue
		}
		count++
		if cfg.verbose || count <= 10 || count%1000 == 0 {
			log.Printf("rewrote packet #%d: %s", count, info)
		}
	}
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

	oldSrc := ipString(pkt[12:16])
	oldDst := ipString(pkt[16:20])

	if !equal4(pkt[16:20], target) {
		return "", false
	}

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
		case 6: // TCP
			if totalLen-ihl >= 20 {
				pkt[ihl+16], pkt[ihl+17] = 0, 0
				binary.BigEndian.PutUint16(pkt[ihl+16:ihl+18], transportChecksum(pkt, ihl, proto))
			}
		case 17: // UDP
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

func equal4(b []byte, ip net.IP) bool {
	return len(b) >= 4 && len(ip) == 4 && b[0] == ip[0] && b[1] == ip[1] && b[2] == ip[2] && b[3] == ip[3]
}

func ipString(b []byte) string {
	if len(b) < 4 {
		return "?.?.?.?"
	}
	return fmt.Sprintf("%d.%d.%d.%d", b[0], b[1], b[2], b[3])
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
	for (sum >> 16) != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	return ^uint16(sum)
}

func transportChecksum(pkt []byte, ihl int, proto byte) uint16 {
	length := len(pkt) - ihl
	pseudo := make([]byte, 0, 12+length+1)
	pseudo = append(pseudo, pkt[12:16]...)
	pseudo = append(pseudo, pkt[16:20]...)
	pseudo = append(pseudo, 0)
	pseudo = append(pseudo, proto)
	pseudo = append(pseudo, byte(length>>8), byte(length))
	pseudo = append(pseudo, pkt[ihl:]...)
	if len(pseudo)%2 == 1 {
		pseudo = append(pseudo, 0)
	}
	return checksum(pseudo)
}
