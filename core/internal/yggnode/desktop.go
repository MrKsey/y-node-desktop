package yggnode

import (
	"context"
	"encoding/binary"
	"encoding/json"
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
//
// A change that only touches the DNS settings keeps the running manager: the
// UDP association, the learned tokens and the health of the exit survive a
// switch between Yggdrasil DNS and the system resolver. Rebuilding the manager
// for such a change used to blank the published resolver for one status poll
// and to send the first lookups to the local resolvers, whose answers were then
// cached for minutes while the traffic already left through the exit.
func (n *Node) SetDesktopExitConfig(raw string) error {
	cfg, err := parseExitConfig(raw)
	if err != nil {
		return err
	}
	n.mu.Lock()
	inner := n.inner
	running := n.running
	manager := n.exit
	router := n.dns
	n.mu.Unlock()
	if !running || inner == nil {
		return errors.New("the node is not running")
	}
	if manager != nil && router != nil && manager.sameProfiles(cfg) {
		manager.updateConfig(cfg)
		router.clearCache()
		n.mu.Lock()
		n.exitRaw = raw
		n.mu.Unlock()
		n.logger.emit("info", "desktop exit DNS settings applied")
		return nil
	}
	direct := newDirectDialer(nil, 15*time.Second)
	// The desktop has no Yggdrasil interface: the node dials in-network
	// destinations itself, and only the rest goes to the operating system.
	direct.inner = inner
	manager, err = newExitManager(raw, inner, direct, n.logger)
	if err != nil {
		return err
	}
	router = newDNSRouter(manager, inner, direct, n.logger)
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
//
// Every address of the name is tried in the order the configuration prefers:
// IPv4 first for an ordinary name, so the traffic stays on the family every
// exit carries, and IPv6 only when no IPv4 address answered or the name has no
// A record at all. The proxy is the only resolver here, so the browser cannot
// make that choice itself the way it does on Android, where the traffic goes
// through the tunnel interface.
func (n *Node) DesktopDial(ctx context.Context, network, address string) (net.Conn, error) {
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return nil, fmt.Errorf("bad destination port %q", portText)
	}
	if ip := net.ParseIP(host); ip != nil {
		return n.dialAddress(ctx, network, ip, port)
	}
	ips, err := n.ResolveHosts(ctx, host)
	if err != nil {
		return nil, err
	}
	var lastErr error
	for _, ip := range ips {
		conn, err := n.dialAddress(ctx, network, ip, port)
		if err == nil {
			return conn, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("cannot reach %s", host)
	}
	return nil, lastErr
}

// dialAddress opens one connection to a resolved address.
func (n *Node) dialAddress(ctx context.Context, network string, ip net.IP, port int) (net.Conn, error) {
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

// ResolveHost resolves one name for the proxy and returns the first address.
func (n *Node) ResolveHost(ctx context.Context, host string) (net.IP, error) {
	ips, err := n.ResolveHosts(ctx, host)
	if err != nil {
		return nil, err
	}
	return ips[0], nil
}

// ResolveHosts resolves one name for the proxy and returns every address in the
// order the configuration prefers. A literal address is returned as it is.
// Yggdrasil names are asked for an AAAA record only.
func (n *Node) ResolveHosts(ctx context.Context, host string) ([]net.IP, error) {
	name := strings.TrimSuffix(strings.TrimSpace(host), ".")
	if name == "" {
		return nil, errors.New("empty host name")
	}
	if ip := net.ParseIP(name); ip != nil {
		return []net.IP{ip}, nil
	}
	n.mu.Lock()
	router := n.dns
	n.mu.Unlock()
	if router == nil {
		return nil, errors.New("DNS is not ready: the node is not running")
	}

	var found []net.IP
	reason := ""
	order, strictFirst := n.resolveOrder(name)
	for index, qtype := range order {
		query := dnsQuery(desktopDNSTxID, name, qtype)
		reply := router.handle(query)
		var ips []net.IP
		if qtype == dnsTypeA {
			ips = dnsRecords(reply, desktopDNSTxID, dnsTypeA, 4)
		} else {
			ips = dnsRecords(reply, desktopDNSTxID, dnsTypeAAAA, 16)
		}
		if len(ips) == 0 && reason == "" && dnsRcode(reply) > 0 {
			// The resolvers answered, but with an error: the proxy log has to
			// say why the name did not resolve instead of only "no answer".
			reason = dnsRcodeText(reply)
		}
		for _, ip := range ips {
			duplicate := false
			for _, known := range found {
				if known.Equal(ip) {
					duplicate = true
					break
				}
			}
			if !duplicate {
				found = append(found, ip)
			}
		}
		// Auto mode is IPv4 only when the name has an IPv4 address: a client
		// must not move the traffic to IPv6 just because the exit reports a
		// working IPv6 route. The AAAA query is asked only when the name has no
		// A record at all.
		if strictFirst && index == 0 && len(ips) > 0 {
			break
		}
	}
	if len(found) == 0 {
		if reason != "" {
			return nil, fmt.Errorf("no answer for %s (%s)", name, reason)
		}
		return nil, fmt.Errorf("no answer for %s", name)
	}
	return found, nil
}

// resolveOrder is the address family order of one name. Yggdrasil names have no
// IPv4 form at all and are always asked for an AAAA record.
//
// Auto mode always puts IPv4 first and never switches a name that has an IPv4
// address to IPv6: the second result is true, which tells ResolveHosts to stop
// after a successful A answer. IPv6 is asked only for a name without an A
// record. The exit's own IPv6 capability does not change that order; it only
// decides whether IPv6 destinations are forwarded at all.
//
// The "prefer" mode of the local configuration is the explicit opt-in for the
// opposite order: AAAA first, then A, and both families are used. "Off" drops
// IPv6 entirely.
func (n *Node) resolveOrder(name string) ([]uint16, bool) {
	if isYggName(name) {
		return []uint16{dnsTypeAAAA}, false
	}
	mode := "auto"
	n.mu.Lock()
	manager := n.exit
	n.mu.Unlock()
	if manager != nil {
		mode = manager.config().ipv6Mode()
	}
	switch mode {
	case "off":
		return []uint16{dnsTypeA}, false
	case "prefer":
		return []uint16{dnsTypeAAAA, dnsTypeA}, false
	}
	return []uint16{dnsTypeA, dnsTypeAAAA}, true
}

// DesktopExitEnabled reports whether the exit manager exists and is switched on.
func (n *Node) DesktopExitEnabled() bool {
	n.mu.Lock()
	manager := n.exit
	n.mu.Unlock()
	return manager != nil && manager.enabled()
}

// CheckSystemDNS probes one ordinary resolver directly and reports how fast it
// answered. A Yggdrasil resolver needs the node and is checked with CheckDNS.
func (n *Node) CheckSystemDNS(server string, timeoutMs int) string {
	if timeoutMs < 1000 {
		timeoutMs = 8000
	}
	if timeoutMs > 30000 {
		timeoutMs = 30000
	}
	server = strings.TrimSpace(server)
	if server == "" {
		return `{"ok":false,"error":"empty_server"}`
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	address := dnsEndpoint(server)
	dialer := net.Dialer{Timeout: 8 * time.Second}
	started := time.Now()
	query := dnsQuery(desktopDNSTxID+1, "example.com", dnsTypeA)
	response, err := queryDNSUpstream(ctx, dialer.DialContext, address, query)
	ms := float64(time.Since(started).Microseconds()) / 1000
	if err != nil {
		payload, _ := json.Marshal(map[string]any{
			"ok": false, "server": server, "ms": ms, "error": err.Error(),
		})
		return string(payload)
	}
	if len(response) < 12 || binary.BigEndian.Uint16(response[2:4])&0x000F != 0 {
		payload, _ := json.Marshal(map[string]any{
			"ok": false, "server": server, "ms": ms,
			"error": "the server answered with an error",
		})
		return string(payload)
	}
	addressText := ""
	if ip := firstDNSAddress(response, desktopDNSTxID+1); ip != nil {
		addressText = ip.String()
	}
	payload, _ := json.Marshal(map[string]any{
		"ok": true, "server": server, "ms": ms, "address": addressText,
	})
	return string(payload)
}
