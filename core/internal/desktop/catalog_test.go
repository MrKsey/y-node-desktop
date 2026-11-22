package desktop

import "testing"

func TestBestPerHostKeepsTheBestTransport(t *testing.T) {
	peers := []CatalogPeer{
		{URI: "quic://a.example:1", Host: "a.example", Scheme: "quic"},
		{URI: "tcp://a.example:2", Host: "a.example", Scheme: "tcp"},
		{URI: "tls://a.example:3", Host: "a.example", Scheme: "tls"},
		{URI: "wss://b.example:443", Host: "b.example", Scheme: "wss"},
	}
	got := bestPerHost(peers)
	if len(got) != 2 {
		t.Fatalf("bestPerHost returned %d rows, want 2: %v", len(got), got)
	}
	if got[0].URI != "tls://a.example:3" {
		t.Fatalf("the first host kept %q, want the tls transport", got[0].URI)
	}
	if got[1].URI != "wss://b.example:443" {
		t.Fatalf("the second host = %q, want the untouched row", got[1].URI)
	}
}

func TestBestPerHostIgnoresRowsWithoutAHost(t *testing.T) {
	got := bestPerHost([]CatalogPeer{{URI: "tls:///broken"}, {URI: "tls://a.example:1", Host: "a.example", Scheme: "tls"}})
	if len(got) != 1 || got[0].Host != "a.example" {
		t.Fatalf("bestPerHost = %v, want only the row with a host", got)
	}
}

// A country with more servers than the limit keeps the first ones, and the
// neighbours never push a home server out of the round.
func TestDiscoveryTargetsCoversEveryHomeServer(t *testing.T) {
	peers := []CatalogPeer{
		{URI: "tls://msk-1.example:1", Host: "msk-1.example", Country: "russia", Scheme: "tls"},
		{URI: "tcp://msk-1.example:2", Host: "msk-1.example", Country: "russia", Scheme: "tcp"},
		{URI: "tls://msk-2.example:1", Host: "msk-2.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://spb-1.example:1", Host: "spb-1.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://fi-1.example:1", Host: "fi-1.example", Country: "finland", Scheme: "tls"},
		{URI: "tls://am-1.example:1", Host: "am-1.example", Country: "armenia", Scheme: "tls"},
	}
	got := discoveryTargets(peers, "russia", 4)
	if len(got) != 4 {
		t.Fatalf("targets = %d, want the limit 4: %v", len(got), got)
	}
	hosts := map[string]bool{}
	for _, uri := range got {
		hosts[peerHost(uri)] = true
	}
	for _, host := range []string{"msk-1.example", "msk-2.example", "spb-1.example"} {
		if !hosts[host] {
			t.Fatalf("the home server %s is missing from %v", host, got)
		}
	}
}

func TestDiscoveryTargetsFallsBackToTheClosestCountries(t *testing.T) {
	peers := []CatalogPeer{
		{URI: "tls://fi-1.example:1", Host: "fi-1.example", Country: "finland", Scheme: "tls"},
		{URI: "tls://de-1.example:1", Host: "de-1.example", Country: "germany", Scheme: "tls"},
	}
	got := discoveryTargets(peers, "russia", 10)
	if len(got) != 2 {
		t.Fatalf("targets = %v, want both neighbours when the home country is empty", got)
	}
}

// A country with more servers than the round can test still leaves part of the
// window to the closest foreign countries: the nearest peers may sit across the
// border, so the round must be able to compare them with the local ones.
func TestDiscoveryTargetsKeepsRoomForTheClosestCountries(t *testing.T) {
	var peers []CatalogPeer
	for _, host := range []string{"ru-1", "ru-2", "ru-3", "ru-4", "ru-5", "ru-6", "ru-7", "ru-8"} {
		peers = append(peers, CatalogPeer{
			URI:     "tls://" + host + ".example:1",
			Host:    host + ".example",
			Country: "russia",
			Scheme:  "tls",
		})
	}
	peers = append(peers,
		CatalogPeer{URI: "tls://fi-1.example:1", Host: "fi-1.example", Country: "finland", Scheme: "tls"},
		CatalogPeer{URI: "tls://de-1.example:1", Host: "de-1.example", Country: "germany", Scheme: "tls"},
	)
	got := discoveryTargets(peers, "russia", 8)
	if len(got) != 8 {
		t.Fatalf("targets = %d, want the limit 8: %v", len(got), got)
	}
	hosts := map[string]bool{}
	for _, uri := range got {
		hosts[peerHost(uri)] = true
	}
	if !hosts["fi-1.example"] || !hosts["de-1.example"] {
		t.Fatalf("the closest countries are missing from %v", got)
	}
	if !hosts["ru-1.example"] {
		t.Fatalf("the home servers are missing from %v", got)
	}
}

func TestDiscoveryTargetsRespectsTheLimit(t *testing.T) {
	var peers []CatalogPeer
	for _, host := range []string{"a", "b", "c", "d", "e"} {
		peers = append(peers, CatalogPeer{
			URI:     "tls://" + host + ".example:1",
			Host:    host + ".example",
			Country: "russia",
			Scheme:  "tls",
		})
	}
	if got := discoveryTargets(peers, "russia", 3); len(got) != 3 {
		t.Fatalf("targets = %v, want 3", got)
	}
}

// The catalogue is ranked around the detected location: the home country comes
// first, then the countries nearest to it. A large country must not beat a
// neighbouring one that is physically closer to the user.
func TestRankCatalogPutsTheClosestCountriesFirst(t *testing.T) {
	app := &App{geo: &geoLocation{CountrySlug: "russia", Lat: 60.17, Lon: 24.94}}
	peers := []CatalogPeer{
		{URI: "tls://ru-far.example:1", Host: "ru-far.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://fi-1.example:1", Host: "fi-1.example", Country: "finland", Scheme: "tls"},
		{URI: "tls://de-1.example:1", Host: "de-1.example", Country: "germany", Scheme: "tls"},
		{URI: "tls://ru-home.example:1", Host: "ru-home.example", Country: "russia", Scheme: "tls"},
	}
	got := app.rankCatalog(peers)
	if len(got) != 4 {
		t.Fatalf("ranked = %v", got)
	}
	if got[0].Country != "russia" || got[1].Country != "russia" {
		t.Fatalf("the home country must come first: %v", got)
	}
	if got[2].Country != "finland" || got[3].Country != "germany" {
		t.Fatalf("the closest countries must follow the home one: %v", got)
	}
}

// The round must test the nearest foreign countries, not the farthest ones: the
// order of the ranked catalogue decides which countries get the spare window.
func TestDiscoveryTargetsProbesTheClosestCountries(t *testing.T) {
	app := &App{geo: &geoLocation{CountrySlug: "russia", Lat: 60.17, Lon: 24.94}}
	peers := []CatalogPeer{
		{URI: "tls://ru-1.example:1", Host: "ru-1.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://ru-2.example:1", Host: "ru-2.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://ru-3.example:1", Host: "ru-3.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://ru-4.example:1", Host: "ru-4.example", Country: "russia", Scheme: "tls"},
		{URI: "tls://fi-1.example:1", Host: "fi-1.example", Country: "finland", Scheme: "tls"},
		{URI: "tls://br-1.example:1", Host: "br-1.example", Country: "brazil", Scheme: "tls"},
	}
	got := discoveryTargets(app.rankCatalog(peers), "russia", 5)
	hosts := map[string]bool{}
	for _, uri := range got {
		hosts[peerHost(uri)] = true
	}
	if !hosts["fi-1.example"] {
		t.Fatalf("the nearest foreign country is missing from %v", got)
	}
	if hosts["br-1.example"] {
		t.Fatalf("the farthest country took the window instead of a closer one: %v", got)
	}
}
