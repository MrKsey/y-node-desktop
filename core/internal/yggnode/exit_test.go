package yggnode

import (
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"testing"
	"time"
)

func TestParseExitConfig(t *testing.T) {
	raw := `{
		"enabled": true,
		"profiles": [
			{"name": "first", "address": "200::1", "socksPort": 1080, "apiPort": 1081},
			{"name": "second", "address": "200::2", "socksPort": 1080, "apiPort": 1081}
		],
		"activeId": "200::2:1080",
		"fallbackDirect": true
	}`
	cfg, err := parseExitConfig(raw)
	if err != nil {
		t.Fatalf("parseExitConfig: %v", err)
	}
	if !cfg.Enabled || !cfg.FallbackDirect {
		t.Fatalf("flags were lost: %+v", cfg)
	}
	if cfg.Profiles[0].ID != "200::1:1080" {
		t.Fatalf("default id = %q", cfg.Profiles[0].ID)
	}
	// No exit resolver is configured, so ordinary names must use the system
	// resolvers rather than a hidden 1.1.1.1 default.
	if len(cfg.DNS) != 0 {
		t.Fatalf("an empty DNS list gained servers: %v", cfg.DNS)
	}
	explicit, err := parseExitConfig(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}],"dns":["9.9.9.9"]}`)
	if err != nil {
		t.Fatalf("parseExitConfig: %v", err)
	}
	if len(explicit.DNS) != 1 || explicit.DNS[0] != "9.9.9.9" {
		t.Fatalf("explicit DNS = %v", explicit.DNS)
	}
}

func TestParseExitConfigRejectsBadProfile(t *testing.T) {
	_, err := parseExitConfig(`{"enabled":true,"profiles":[{"address":"10.0.0.1","socksPort":1080,"apiPort":1081}]}`)
	if err == nil {
		t.Fatal("a non-Yggdrasil exit address was accepted")
	}
	_, err = parseExitConfig(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":0,"apiPort":1081}]}`)
	if err == nil {
		t.Fatal("a zero SOCKS port was accepted")
	}
}

// TestUpdateConfigKeepsHealth covers the DNS-mode switch: the resolver lists
// change, the exit does not, so the running manager keeps the relay and the
// measured state instead of being rebuilt for one poll.
func TestUpdateConfigKeepsHealth(t *testing.T) {
	before, err := parseExitConfig(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}],"activeId":"200::1:1080","dnsMode":"yggdrasil"}`)
	if err != nil {
		t.Fatalf("parseExitConfig: %v", err)
	}
	manager := &exitManager{
		cfg:    before,
		health: map[string]*profileHealth{"200::1:1080": {State: exitStateOnline, LatencyMs: 42}},
		tokens: map[string]string{"200::1:1080": "secret"},
	}
	after, err := parseExitConfig(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}],"activeId":"200::1:1080","dnsMode":"system","systemDns":["192.168.1.2"]}`)
	if err != nil {
		t.Fatalf("parseExitConfig: %v", err)
	}
	if !manager.sameProfiles(after) {
		t.Fatal("a DNS-only change was treated as a profile change")
	}
	manager.updateConfig(after)
	if manager.config().dnsMode() != "system" {
		t.Fatalf("dns mode = %q", manager.config().dnsMode())
	}
	if health := manager.health["200::1:1080"]; health == nil || health.State != exitStateOnline || health.LatencyMs != 42 {
		t.Fatalf("health was lost: %+v", health)
	}
	if manager.profileToken(ExitProfile{ID: "200::1:1080"}) != "secret" {
		t.Fatal("the learned token was lost")
	}

	renamed, err := parseExitConfig(`{"enabled":true,"profiles":[{"name":"renamed","address":"200::1","socksPort":1080,"apiPort":1081}],"activeId":"200::1:1080"}`)
	if err != nil {
		t.Fatalf("parseExitConfig: %v", err)
	}
	if manager.sameProfiles(renamed) {
		t.Fatal("a renamed profile kept the old manager")
	}
}

func TestExitStatusReportsSuspension(t *testing.T) {
	manager := &exitManager{
		cfg: exitConfig{
			Enabled:  true,
			Profiles: []ExitProfile{{ID: "a", Name: "a"}},
		},
		health: map[string]*profileHealth{
			"a": {State: exitStateOnline, Suspended: true},
		},
	}
	status := manager.status()
	if len(status.Profiles) != 1 {
		t.Fatalf("profiles = %d", len(status.Profiles))
	}
	if !status.Profiles[0].Suspended {
		t.Fatal("the suspension of the client was not published")
	}
}

// Only the selected profile carries traffic: the other configured nodes wait
// for a switch and are not a failover chain, so a node the user did not pick
// never sees the traffic.
func TestExitUsesOnlyTheActiveProfile(t *testing.T) {
	manager := &exitManager{
		cfg: exitConfig{
			Profiles: []ExitProfile{
				{ID: "a", Name: "a"},
				{ID: "b", Name: "b"},
				{ID: "c", Name: "c"},
			},
			ActiveID: "b",
		},
	}
	active := manager.activeProfiles()
	if len(active) != 1 || active[0].ID != "b" {
		t.Fatalf("active profiles = %+v, want only b", active)
	}
}

// A stored id that matches no profile (an old configuration, or a profile
// removed while the tunnel was up) falls back to the first one, which is what
// the app shows as active too.
func TestExitActiveFallsBackToTheFirstProfile(t *testing.T) {
	manager := &exitManager{
		cfg: exitConfig{
			Profiles: []ExitProfile{{ID: "a"}, {ID: "b"}},
			ActiveID: "gone",
		},
	}
	active := manager.activeProfiles()
	if len(active) != 1 || active[0].ID != "a" {
		t.Fatalf("active profiles = %+v, want only a", active)
	}
	if active := (&exitManager{}).activeProfiles(); active != nil {
		t.Fatalf("an exit without profiles returned %+v", active)
	}
}

func TestExitCarriesIPv6OnlyWhenEnabled(t *testing.T) {
	manager, err := newExitManager(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	if !manager.carriesIPv6() {
		t.Fatal("an enabled exit must carry IPv6")
	}
	disabled, err := newExitManager(`{"enabled":false,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	if disabled.carriesIPv6() {
		t.Fatal("a disabled exit must not carry IPv6")
	}
	empty, err := newExitManager(`{"enabled":true,"profiles":[]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	if empty.carriesIPv6() {
		t.Fatal("an exit without profiles must not carry IPv6")
	}
}

// The exit tells the client whether its own host can reach IPv6. A broken
// provider is the case that used to look healthy: the interface is up, but
// every packet is dropped, so the tunnel must stop sending IPv6.
func TestExitCarriesIPv6FollowsExitCapabilities(t *testing.T) {
	manager, err := newExitManager(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{IPv6: false, IPv6State: "broken"})
	if manager.carriesIPv6() {
		t.Fatal("IPv6 was carried after the exit reported a broken route")
	}
	status := manager.status()
	if status.Profiles[0].IPv6Available == nil || *status.Profiles[0].IPv6Available {
		t.Fatalf("ipv6Available = %v", status.Profiles[0].IPv6Available)
	}
	if status.Profiles[0].IPv6State != "broken" {
		t.Fatalf("ipv6State = %q", status.Profiles[0].IPv6State)
	}
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{IPv6: true, IPv6State: "ok"})
	if !manager.carriesIPv6() {
		t.Fatal("IPv6 was not restored after the exit recovered")
	}
	// A status without capabilities (an old exit, or one answered without a
	// token) must not change the decision.
	manager.markCapabilities("200::1:1080", nil)
	if !manager.carriesIPv6() {
		t.Fatal("a status without capabilities disabled IPv6")
	}
}

// IPv6 follows the selected profile only. Another node with a working IPv6
// path must not keep the tunnel sending IPv6: that traffic would leave through
// a node the user did not pick.
func TestExitCarriesIPv6FollowsTheActiveProfile(t *testing.T) {
	const config = `{"enabled":true,"activeId":"200::2:1080","profiles":[
		{"address":"200::1","socksPort":1080,"apiPort":1081},
		{"address":"200::2","socksPort":1080,"apiPort":1081}]}`
	manager, err := newExitManager(config, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	// The selected node reports that it has no IPv6, while the other one can
	// carry it: the tunnel must stop sending IPv6 anyway.
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{IPv6: true, IPv6State: "ok"})
	manager.markCapabilities("200::2:1080", &exitAPICapabilities{IPv6: false, IPv6State: "none"})
	if manager.carriesIPv6() {
		t.Fatal("IPv6 was carried although the selected profile has none")
	}
	// A selected profile whose capability is unknown keeps the old behaviour:
	// it may carry IPv6, and a working path must not be disabled.
	unknown, err := newExitManager(config, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	unknown.markCapabilities("200::1:1080", &exitAPICapabilities{IPv6: false, IPv6State: "none"})
	if !unknown.carriesIPv6() {
		t.Fatal("an unpolled active profile must count as a possible IPv6 path")
	}
}

// The desktop proxy resolves names itself, so the browser cannot apply its own
// Happy Eyeballs rule: the family order has to follow what the exit reported.
// An exit with a working IPv6 path gets the AAAA query first, an exit with IPv6
// off gets IPv4 only, and an exit that has not answered yet keeps IPv4 first.
func TestResolveOrderFollowsTheExit(t *testing.T) {
	manager, err := newExitManager(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	node := NewNode()
	node.exit = manager

	order := node.resolveOrder("example.com")
	if len(order) != 2 || order[0] != dnsTypeA {
		t.Fatalf("an unpolled exit order = %v, want A first", order)
	}
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{IPv6: true, IPv6State: "ok"})
	order = node.resolveOrder("example.com")
	if len(order) != 2 || order[0] != dnsTypeAAAA {
		t.Fatalf("an IPv6 exit order = %v, want AAAA first", order)
	}
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{IPv6: false, IPv6State: "off"})
	order = node.resolveOrder("example.com")
	if len(order) != 1 || order[0] != dnsTypeA {
		t.Fatalf("an IPv4-only exit order = %v, want A only", order)
	}

	// Without an exit the machine keeps its own IPv6 path, so both families
	// are still asked for.
	disabled, err := newExitManager(`{"enabled":false,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	direct := NewNode()
	direct.exit = disabled
	order = direct.resolveOrder("example.com")
	if len(order) != 2 || order[0] != dnsTypeA || order[1] != dnsTypeAAAA {
		t.Fatalf("a direct order = %v, want A and AAAA", order)
	}
}

// The exit publishes the resolver it runs for its clients. A profile imported
// before DNS was enabled learns it from the status answer, and a later "DNS is
// off" answer clears it again.
func TestExitStatusCarriesDNSResolver(t *testing.T) {
	manager, err := newExitManager(`{"enabled":true,"profiles":[{"address":"200::1","socksPort":1080,"apiPort":1081}]}`, nil, nil, &goLogger{})
	if err != nil {
		t.Fatal(err)
	}
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{
		DNS:        true,
		DNSAddress: "200::1",
		DNSPort:    5353,
	})
	item := manager.status().Profiles[0]
	if !item.DNSKnown || item.DNSAddress != "200::1" || item.DNSPort != 5353 {
		t.Fatalf("dns = %q:%d known=%v", item.DNSAddress, item.DNSPort, item.DNSKnown)
	}
	manager.markCapabilities("200::1:1080", &exitAPICapabilities{DNS: false})
	item = manager.status().Profiles[0]
	if !item.DNSKnown || item.DNSAddress != "" {
		t.Fatalf("dns = %q known=%v, want it cleared", item.DNSAddress, item.DNSKnown)
	}
}

func TestIsLocalDestination(t *testing.T) {
	for _, value := range []string{"10.1.2.3", "192.168.1.1", "127.0.0.1", "169.254.1.1", "100.64.0.1", "fe80::1", "fc00::1"} {
		if !isLocalDestination(net.ParseIP(value)) {
			t.Errorf("%s should stay on the local network", value)
		}
	}
	for _, value := range []string{"1.1.1.1", "8.8.8.8", "2606:4700:4700::1111"} {
		if isLocalDestination(net.ParseIP(value)) {
			t.Errorf("%s should go through the exit", value)
		}
	}
}

func TestDNSNameClassification(t *testing.T) {
	manager := &exitManager{cfg: exitConfig{LocalDNS: true}}
	router := newDNSRouter(manager, nil, nil, &goLogger{})

	if !isYggName("rutor.ygg") || !isYggName("YGG") {
		t.Error("ygg names were not recognised")
	}
	if isYggName("example.com") {
		t.Error("a public name was taken for a ygg name")
	}
	for _, name := range []string{"printer", "router.lan", "nas.local", "host.home.arpa"} {
		if !router.isLocalName(name) {
			t.Errorf("%s should be resolved by the local DNS", name)
		}
	}
	for _, name := range []string{"example.com", "cdn.example.net"} {
		if router.isLocalName(name) {
			t.Errorf("%s should be resolved by the exit", name)
		}
	}
}

func TestDNSQuestionRoundTrip(t *testing.T) {
	query := dnsQuery(0x1234, "rutor.ygg", 28)
	name, qtype, ok := dnsQuestion(query)
	if !ok || name != "rutor.ygg" || qtype != 28 {
		t.Fatalf("question = %q/%d ok=%v", name, qtype, ok)
	}
	response := servfail(query)
	if len(response) < 12 || response[0] != 0x12 || response[1] != 0x34 {
		t.Fatal("SERVFAIL lost the transaction id")
	}
	flags := binary.BigEndian.Uint16(response[2:4])
	if flags&0x8000 == 0 || flags&0x000F != 2 {
		t.Fatalf("unexpected SERVFAIL flags %#x", flags)
	}
}

func TestSocks5Connect(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	go fakeSocksServer(server, socksReplySuccess)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := socks5Connect(ctx, client, net.ParseIP("1.2.3.4"), 443); err != nil {
		t.Fatalf("socks5Connect: %v", err)
	}
}

func TestSocks5ConnectIPv6(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	want := net.ParseIP("2606:4700:4700::1111")
	go func() {
		defer server.Close()
		greeting := make([]byte, 3)
		if _, err := io.ReadFull(server, greeting); err != nil {
			return
		}
		_, _ = server.Write([]byte{5, 0})
		request := make([]byte, 4+16+2)
		if _, err := io.ReadFull(server, request); err != nil {
			return
		}
		if request[1] != socksCmdConnect || request[3] != socksAtypIPv6 {
			return
		}
		if !net.IP(request[4:20]).Equal(want) || binary.BigEndian.Uint16(request[20:22]) != 443 {
			return
		}
		_, _ = server.Write([]byte{5, socksReplySuccess, 0, 1, 0, 0, 0, 0, 0, 0})
		_, _ = io.Copy(io.Discard, server)
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := socks5Connect(ctx, client, want, 443); err != nil {
		t.Fatalf("socks5Connect over IPv6: %v", err)
	}
}

func TestSocks5ConnectDenied(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	go fakeSocksServer(server, socksReplyNotAllowed)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	err := socks5Connect(ctx, client, net.ParseIP("1.2.3.4"), 443)
	var reply *socksReplyError
	if !errors.As(err, &reply) || reply.Code != socksReplyNotAllowed {
		t.Fatalf("error = %v, want a denied SOCKS reply", err)
	}
}

func fakeSocksServer(conn net.Conn, code byte) {
	defer conn.Close()
	greeting := make([]byte, 3)
	if _, err := io.ReadFull(conn, greeting); err != nil {
		return
	}
	_, _ = conn.Write([]byte{5, 0})
	request := make([]byte, 10)
	if _, err := io.ReadFull(conn, request); err != nil {
		return
	}
	_, _ = conn.Write([]byte{5, code, 0, 1, 0, 0, 0, 0, 0, 0})
}

func TestDNSEndpointKeepsAnExplicitPort(t *testing.T) {
	cases := map[string]string{
		"202::1":        "[202::1]:53",
		"1.1.1.1":       "1.1.1.1:53",
		"[202::1]:5353": "[202::1]:5353",
		"1.1.1.1:5353":  "1.1.1.1:5353",
	}
	for input, want := range cases {
		if got := dnsEndpoint(input); got != want {
			t.Errorf("dnsEndpoint(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestCleanServersKeepsANonDefaultPort(t *testing.T) {
	got := cleanServers([]string{
		"202::1",
		"[202::1]:5353",
		"not-a-server",
		"1.1.1.1:0",
	})
	want := []string{"202::1", "[202::1]:5353"}
	if len(got) != len(want) {
		t.Fatalf("cleanServers = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("cleanServers = %v, want %v", got, want)
		}
	}
}
