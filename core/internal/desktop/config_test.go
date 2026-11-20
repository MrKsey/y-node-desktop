package desktop

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestParseExitLinkKeepsInviteAndPinnedPeer(t *testing.T) {
	const link = "yggnode://exit?a=201%3Abd5a%3Aefe4%3A92c%3A284c%3Abbcd%3A5b53%3Aea3b&api=1080&i=YDKSEVzFUbzefIZh1Cd-T_PaX1DZJkLG6QdG_V5vP9s&n=Finland&p=1080&peer=wss%3A%2F%2F160.20.158.195%3A443%2Fygg%3Fkey%3D50a94406fdb4f5ecd10ca92b0571159d96ce42c9bead755a0f04ec4daa994425&v=1"
	profile, invite, err := ParseExitLink(link)
	if err != nil {
		t.Fatalf("ParseExitLink: %v", err)
	}
	if invite != "YDKSEVzFUbzefIZh1Cd-T_PaX1DZJkLG6QdG_V5vP9s" {
		t.Fatalf("invite = %q", invite)
	}
	if profile.Name != "Finland" || profile.Address != "201:bd5a:efe4:92c:284c:bbcd:5b53:ea3b" {
		t.Fatalf("profile = %+v", profile)
	}
	if profile.Peer == "" || !strings.HasPrefix(profile.Peer, "wss://") {
		t.Fatalf("pinned peer = %q", profile.Peer)
	}
}

func TestConfigThemeFallsBackToAuto(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Theme = "night"
	cfg.normalise()
	if cfg.Theme != "auto" {
		t.Fatalf("theme = %q, want auto", cfg.Theme)
	}
	cfg.Theme = "dark"
	cfg.normalise()
	if cfg.Theme != "dark" {
		t.Fatalf("theme = %q, want dark", cfg.Theme)
	}
}

func TestConfigDefaultsMatchTheAndroidClient(t *testing.T) {
	cfg := DefaultConfig()
	if cfg.PeerCount != 3 || !cfg.PeerAutoReplace {
		t.Fatalf("peer defaults = %d/%v", cfg.PeerCount, cfg.PeerAutoReplace)
	}
	if cfg.DNSMode != "yggdrasil" || !cfg.ExitDNSEnabled || !cfg.ExitUDP {
		t.Fatalf("dns defaults = %q/%v/%v", cfg.DNSMode, cfg.ExitDNSEnabled, cfg.ExitUDP)
	}
	if cfg.IPv6 != "auto" {
		t.Fatalf("ipv6 = %q", cfg.IPv6)
	}
	if cfg.PeerDeadTimeout != "90s" || cfg.PeerCheckInterval != "30s" {
		t.Fatalf("peer timers = %q/%q", cfg.PeerDeadTimeout, cfg.PeerCheckInterval)
	}
}

func TestConfigNormalisesPeerAndDNSFields(t *testing.T) {
	cfg := DefaultConfig()
	cfg.PeerCount = 0
	cfg.DNSMode = "magic"
	cfg.IPv6 = "sometimes"
	cfg.PeerDeadTimeout = "soon"
	cfg.PeerCheckInterval = ""
	cfg.normalise()
	if cfg.PeerCount != 3 || cfg.DNSMode != "yggdrasil" || cfg.IPv6 != "auto" {
		t.Fatalf("normalised = %+v", cfg)
	}
	if cfg.PeerDeadTimeout != "90s" || cfg.PeerCheckInterval != "30s" {
		t.Fatalf("timers = %q/%q", cfg.PeerDeadTimeout, cfg.PeerCheckInterval)
	}
}

func TestExitJSONCarriesTheSwitches(t *testing.T) {
	cfg := DefaultConfig()
	cfg.ExitProfiles = []ExitProfile{{
		ID: "e", Address: "200::1", SocksPort: 1080, APIPort: 1080,
		DNS: "200:abcd::53", DNSPort: 53,
	}}
	cfg.ExitEnabled = true
	cfg.ExitDNS = []string{"1.1.1.1", "9.9.9.9"}
	cfg.ExitDNSEnabled = false
	cfg.ExitUDP = false
	cfg.DNSMode = "custom"
	cfg.IPv6 = "prefer"
	var payload map[string]any
	if err := json.Unmarshal([]byte(cfg.exitJSON()), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["dnsMode"] != "custom" || payload["ipv6"] != "prefer" {
		t.Fatalf("payload = %v", payload)
	}
	if payload["udp"] != false {
		t.Fatalf("udp = %v, want false", payload["udp"])
	}
	// "dns" is the public resolver list the exit queries over its relay.
	if dns, ok := payload["dns"].([]any); !ok || len(dns) != 2 {
		t.Fatalf("public resolvers = %v", payload["dns"])
	}
	// The resolver the exit publishes is an in-network one: it belongs to the
	// Yggdrasil list and only when the switch is on.
	if ygg, ok := payload["yggDns"].([]any); !ok {
		t.Fatalf("yggDns = %v", payload["yggDns"])
	} else {
		for _, item := range ygg {
			if item == "200:abcd::53" {
				t.Fatalf("a disabled exit resolver was still sent: %v", ygg)
			}
		}
	}
	cfg.ExitDNSEnabled = true
	if err := json.Unmarshal([]byte(cfg.exitJSON()), &payload); err != nil {
		t.Fatal(err)
	}
	found := false
	if ygg, ok := payload["yggDns"].([]any); ok {
		for _, item := range ygg {
			if item == "200:abcd::53" {
				found = true
			}
		}
	}
	if !found {
		t.Fatalf("the published resolver is missing from yggDns: %v", payload["yggDns"])
	}
}

func TestPeerListAddsOnlyTheActiveExitPeer(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Peers = []string{"tls://public.example:13338"}
	cfg.ExitProfiles = []ExitProfile{
		{ID: "a", Address: "200::1", Peer: "tls://exit-a.example:13338"},
		{ID: "b", Address: "200::2", Peer: "tls://exit-b.example:13338"},
	}
	cfg.ExitActiveID = "b"
	cfg.ExitEnabled = true
	peers := cfg.peerList()
	if len(peers) != 2 {
		t.Fatalf("peers = %v", peers)
	}
	if peers[1] != "tls://exit-b.example:13338" {
		t.Fatalf("the pinned peer is not the active one: %v", peers)
	}
}
