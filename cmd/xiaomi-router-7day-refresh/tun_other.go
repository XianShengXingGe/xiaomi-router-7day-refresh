//go:build !linux

package main

import (
	"errors"
	"log"
	"os"
)

func openTun(name string) (*os.File, string, error) {
	return nil, "", errors.New("TUN interface is only supported on Linux")
}

func runDHCP121Injector(c dhcpConfig) {
	log.Fatalf("DHCP121 injector is only supported on Linux")
}
