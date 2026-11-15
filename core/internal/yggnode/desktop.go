package yggnode

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"
)

// desktopDNSTxID is the transaction id the desktop resolver uses for its own
// queries. It only has to differ from the ids the DNS check uses.
const desktopDNSTxID = 0x5948

// This file is the desktop half of the bridge. The Android build forwards
// traffic through the VpnService file descriptor; a desktop has no TUN, so the
// core process keeps the same Yggdrasil node and the same exit manager and
// exposes one dial function to the local HTTP/SOCKS5 proxy instead.

// StartDesktopPump drains the tunnel so the internal userspace stack receives
// its packets. A desktop has no TUN: everything that is not owned by the
// internal stack is a response nobody is waiting for and is dropped.
func (n *Node) StartDesktopPump() {
	go func() {
		buf := make([]byte, 65535)
		for n.IsRunning() {
			if _, err := n.Recv(buf); err != nil {
				return
			}
		}
	}()
}

// SetDesktopExitConfig installs the exit profile list and the DNS router. It is
// the desktop counterpart of SetExitConfig: no forwarding stack is built,
// because the proxy dials through the exit manager directly.
func (n *Node) SetDesktopExitConfig(raw string) error {
	if _, err := parseExitConfig(raw); err != nil {
		return err
	}
	n.mu.Lock()
	inner := n.inner
	running := n.running
	n.mu.Unlock()
	if !running || inner == nil {
		return errors.New("the node is not running")
	}
	direct := newDirectDialer(nil, 15*time.Second)
	manager, err := newExitManager(raw, inner, direct, n.logger)
	if err != nil {
		return err
	}
	router := newDNSRouter(manager, inner, direct, n.logger)
	n.mu.Lock()
	n.exit = manager
	n.dns = router
	n.exitRaw = raw
	n.mu.Unlock()
	n.logger.emit("info", "desktop exit configuration applied")
	return nil
}

// DesktopDial opens one connection for the local proxy. A Yggdrasil address is
// dialled through the node itself; an ordinary address goes through the exit
// node when one is enabled and directly otherwise. Names are resolved first:
// .ygg names through the in-network resolvers, ordinary names through the exit
// or the system resolver, depending on the configuration.
func (n *Node) DesktopDial(ctx context.Context, network, address string) (net.Conn, error) {
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return nil, fmt.Errorf("bad destination port %q", portText)
	}
	ip := net.ParseIP(host)
	if ip == nil {
		ip, err = n.ResolveHost(ctx, host)
		if err != nil {
			return nil, err
		}
	}
	target := net.JoinHostPort(ip.String(), strconv.Itoa(port))

	if yggRange.Contains(ip) {
		inner := n.internal()
		if inner == nil {
			return nil, errors.New("the node is not running")
		}
		return inner.dialContext(ctx, network, target)
	}

	n.mu.Lock()
	manager := n.exit
	n.mu.Unlock()
	if manager != nil && manager.enabled() {
		return manager.DialContext(ctx, network, target)
	}
	dialer := net.Dialer{Timeout: 15 * time.Second}
	return dialer.DialContext(ctx, network, target)
}

// ResolveHost resolves one name for the proxy. A literal address is returned as
// it is. Yggdrasil names are asked for an AAAA record only; ordinary names try
// A first, because the exit node may not carry IPv6.
func (n *Node) ResolveHost(ctx context.Context, host string) (net.IP, error) {
	name := strings.TrimSuffix(strings.TrimSpace(host), ".")
	if name == "" {
		return nil, errors.New("empty host name")
	}
	if ip := net.ParseIP(name); ip != nil {
		return ip, nil
	}
	n.mu.Lock()
	router := n.dns
	n.mu.Unlock()
	if router == nil {
		return nil, errors.New("DNS is not ready: the node is not running")
	}

	qtypes := []uint16{dnsTypeA, dnsTypeAAAA}
	if isYggName(name) {
		qtypes = []uint16{dnsTypeAAAA}
	}
	var lastErr error
	for _, qtype := range qtypes {
		query := dnsQuery(desktopDNSTxID, name, qtype)
		reply := router.handle(query)
		var ip net.IP
		if qtype == dnsTypeA {
			ip = firstDNSAddress(reply, desktopDNSTxID)
		} else {
			ip = firstDNSAAAA(reply, desktopDNSTxID)
		}
		if ip != nil {
			return ip, nil
		}
		lastErr = fmt.Errorf("no answer for %s", name)
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("cannot resolve %s", name)
	}
	return nil, lastErr
}

// DesktopExitEnabled reports whether the exit manager exists and is switched on.
func (n *Node) DesktopExitEnabled() bool {
	n.mu.Lock()
	manager := n.exit
	n.mu.Unlock()
	return manager != nil && manager.enabled()
}
