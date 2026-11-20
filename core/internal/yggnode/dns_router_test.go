package yggnode

import (
	"net"
	"sync/atomic"
	"testing"
	"time"
)

// flakyResolver answers the first query with SERVFAIL and every later one with
// a real address, the way a resolver that is momentarily out of quota behaves.
type flakyResolver struct {
	conn  *net.UDPConn
	calls atomic.Int32
	done  chan struct{}
}

func newFlakyResolver(t *testing.T, ip net.IP) *flakyResolver {
	t.Helper()
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	resolver := &flakyResolver{conn: conn, done: make(chan struct{})}
	go func() {
		defer close(resolver.done)
		buf := make([]byte, 512)
		for {
			n, from, err := conn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			query := append([]byte(nil), buf[:n]...)
			var reply []byte
			if resolver.calls.Add(1) == 1 {
				reply = servfail(query)
			} else {
				reply = dnsAnswerMessage(query, dnsTypeA, []net.IP{ip})
			}
			if len(reply) > 0 {
				_, _ = conn.WriteToUDP(reply, from)
			}
		}
	}()
	t.Cleanup(func() {
		_ = conn.Close()
		<-resolver.done
	})
	return resolver
}

func (f *flakyResolver) address() string { return f.conn.LocalAddr().String() }

// TestDNSRouterDoesNotCacheAnErrorAnswer is the regression of "CONNECT
// gitlab.com:443: no answer": a resolver that answered SERVFAIL once used to
// have that answer cached for half a minute, so every retry of the browser hit
// the same error and the log said nothing.
func TestDNSRouterDoesNotCacheAnErrorAnswer(t *testing.T) {
	resolver := newFlakyResolver(t, net.ParseIP("93.184.216.34"))
	manager, err := newExitManager(
		`{"enabled":false,"profiles":[],"dns":["`+resolver.address()+`"],"systemDns":["`+resolver.address()+`"]}`,
		nil, nil, &goLogger{},
	)
	if err != nil {
		t.Fatalf("newExitManager: %v", err)
	}
	router := newDNSRouter(manager, nil, newDirectDialer(nil, 2*time.Second), &goLogger{})
	query := dnsQuery(desktopDNSTxID, "flaky.invalid", dnsTypeA)

	first := router.handle(query)
	if got := dnsRcode(first); got != 2 {
		t.Fatalf("first answer rcode = %d, want SERVFAIL", got)
	}
	if len(router.cache) != 0 {
		t.Fatalf("an error answer was cached: %d entries", len(router.cache))
	}

	// The same question again: the resolver recovered, so the real address has
	// to be returned instead of the remembered failure.
	second := router.handle(query)
	address := firstDNSAddress(second, desktopDNSTxID)
	if address == nil || !address.Equal(net.ParseIP("93.184.216.34")) {
		t.Fatalf("second answer = %v (rcode %d)", address, dnsRcode(second))
	}
	if len(router.cache) != 1 {
		t.Fatalf("a real answer was not cached: %d entries", len(router.cache))
	}
}
