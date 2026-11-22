package desktop

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// CatalogPeer is one row of the public peer list with the place it belongs to.
// The list is a repository of markdown files, one per country, grouped into
// continent directories; every file has "### City" headings followed by bullet
// lists that end in backticked connection strings.
type CatalogPeer struct {
	URI         string `json:"uri"`
	Host        string `json:"host"`
	Country     string `json:"country"`
	CountryName string `json:"countryName"`
	Flag        string `json:"flag"`
	City        string `json:"city"`
	Scheme      string `json:"scheme"`
	Port        int    `json:"port"`
}

var catalogPeerPattern = regexp.MustCompile("`((?:tcp|tls|quic|ws|wss)://[^`\\s]+)`")

// PublicPeersCatalog downloads the list and returns every transport with its
// country and city. The result is cached for ten minutes: the page asks for it
// on every visit and the archive is several megabytes.
func (a *App) PublicPeersCatalog() ([]CatalogPeer, time.Time, error) {
	// The ranking needs the detected country: load it before the list is
	// ordered, so the first visit already puts the local peers first.
	a.Geo()
	a.catalogMu.Lock()
	cached := a.catalog
	cachedAt := a.catalogAt
	a.catalogMu.Unlock()
	if len(cached) > 0 && time.Since(cachedAt) < 10*time.Minute {
		return a.rankCatalog(cached), cachedAt, nil
	}

	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Get(publicPeersURL)
	if err != nil {
		if len(cached) > 0 {
			return a.rankCatalog(cached), cachedAt, nil
		}
		if stored := a.readCatalogCache(); len(stored) > 0 {
			return a.rankCatalog(stored), time.Time{}, nil
		}
		return nil, time.Time{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		if len(cached) > 0 {
			return a.rankCatalog(cached), cachedAt, nil
		}
		if stored := a.readCatalogCache(); len(stored) > 0 {
			return a.rankCatalog(stored), time.Time{}, nil
		}
		return nil, time.Time{}, fmt.Errorf("the peer list answered %s", response.Status)
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, 32<<20))
	if err != nil {
		return nil, time.Time{}, err
	}
	peers := parseCatalogArchive(raw)
	if len(peers) == 0 {
		if len(cached) > 0 {
			return a.rankCatalog(cached), cachedAt, nil
		}
		if stored := a.readCatalogCache(); len(stored) > 0 {
			return a.rankCatalog(stored), time.Time{}, nil
		}
		return nil, time.Time{}, errors.New("the peer list has no usable peers")
	}
	a.catalogMu.Lock()
	a.catalog = peers
	a.catalogAt = time.Now()
	a.catalogMu.Unlock()
	a.storeCatalogCache(peers)
	return a.rankCatalog(peers), a.catalogAt, nil
}

// catalogCachePath is the offline copy of the list: without it a start without
// network leaves the Peers page and the exit flag empty.
func catalogCachePath() (string, error) {
	dir, err := ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "catalog.json"), nil
}

func (a *App) readCatalogCache() []CatalogPeer {
	path, err := catalogCachePath()
	if err != nil {
		return nil
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var peers []CatalogPeer
	if err := json.Unmarshal(raw, &peers); err != nil {
		return nil
	}
	a.catalogMu.Lock()
	a.catalog = peers
	a.catalogAt = time.Now().Add(-9 * time.Minute)
	a.catalogMu.Unlock()
	return peers
}

func (a *App) storeCatalogCache(peers []CatalogPeer) {
	path, err := catalogCachePath()
	if err != nil {
		return
	}
	raw, err := json.Marshal(peers)
	if err != nil {
		return
	}
	_ = os.WriteFile(path, raw, 0o600)
}

// rankCatalog puts the peers of the selected country first and then orders them
// by the distance from the detected location, exactly like the Android client.
func (a *App) rankCatalog(peers []CatalogPeer) []CatalogPeer {
	a.mu.Lock()
	selected := a.cfg.CountrySlug
	a.mu.Unlock()
	a.geoMu.Lock()
	geo := a.geo
	a.geoMu.Unlock()
	if selected == "" && geo != nil {
		// The user has not picked a country: rank around the detected one, the
		// way the Android client does. Without it the centroid of a large
		// country can look farther away than a neighbouring country.
		selected = geo.CountrySlug
	}

	out := append([]CatalogPeer(nil), peers...)
	distance := func(peer CatalogPeer) float64 {
		if geo == nil {
			return 0
		}
		item, ok := countryBySlug(peer.Country)
		if !ok {
			return 20000
		}
		return distanceKm(geo.Lat, geo.Lon, item.Lat, item.Lon)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if selected != "" {
			left := out[i].Country == selected
			right := out[j].Country == selected
			if left != right {
				return left
			}
		}
		delta := distance(out[i]) - distance(out[j])
		if delta > 1 {
			return false
		}
		if delta < -1 {
			return true
		}
		if out[i].Country != out[j].Country {
			return out[i].Country < out[j].Country
		}
		if out[i].City != out[j].City {
			return out[i].City < out[j].City
		}
		return out[i].URI < out[j].URI
	})
	return out
}

// bestPerHost keeps one URI per server: the catalogue lists every transport of
// a node as a separate row, and probing three ports of the same machine spends
// the round without adding a peer. The first row keeps its place in the order,
// the best transport of that host wins.
func bestPerHost(peers []CatalogPeer) []CatalogPeer {
	out := make([]CatalogPeer, 0, len(peers))
	index := make(map[string]int, len(peers))
	for _, peer := range peers {
		host := strings.ToLower(strings.TrimSpace(peer.Host))
		if host == "" {
			continue
		}
		if at, ok := index[host]; ok {
			if schemeRank[peer.Scheme] < schemeRank[out[at].Scheme] {
				out[at] = peer
			}
			continue
		}
		index[host] = len(out)
		out = append(out, peer)
	}
	return out
}

// discoveryTargets picks the servers of one discovery round: the nodes of the
// home country first and the closest countries next, one URI per server. The
// country is only a prior, not the answer: the nearest peers may sit across the
// border, and a large country has servers on the other side of the continent,
// so a quarter of the window is always kept for the closest foreign countries.
// A user whose country has no peers at all gets the closest countries instead.
func discoveryTargets(peers []CatalogPeer, home string, limit int) []string {
	if limit < 1 || len(peers) == 0 {
		return nil
	}
	unique := bestPerHost(peers)
	out := make([]string, 0, limit)
	seen := make(map[string]bool, len(unique))
	homeBudget := limit
	if home != "" {
		homeBudget = limit - limit/4
		if homeBudget < 1 {
			homeBudget = 1
		}
	}
	if home != "" {
		for _, peer := range unique {
			if peer.Country != home {
				continue
			}
			seen[peer.Host] = true
			out = append(out, peer.URI)
			if len(out) >= homeBudget {
				break
			}
		}
		// The rest of the window goes to the closest countries in the ranked
		// order, so the round can compare a local server with a faster one on
		// the other side of the border.
		for _, peer := range unique {
			if len(out) >= limit {
				break
			}
			if peer.Country == home || seen[peer.Host] {
				continue
			}
			seen[peer.Host] = true
			out = append(out, peer.URI)
		}
		return out
	}
	for _, peer := range unique {
		if len(out) >= limit {
			break
		}
		if seen[peer.Host] {
			continue
		}
		seen[peer.Host] = true
		out = append(out, peer.URI)
	}
	return out
}

// DiscoveryTargets returns the peers a discovery round should probe. The
// country of the user comes from the switch of the Peers page or from GeoIP,
// the same choice rankCatalog makes.
func (a *App) DiscoveryTargets(limit int) []string {
	if limit < 1 {
		limit = 60
	}
	peers, _, err := a.PublicPeersCatalog()
	if err != nil || len(peers) == 0 {
		return nil
	}
	a.mu.Lock()
	home := a.cfg.CountrySlug
	a.mu.Unlock()
	if home == "" {
		a.geoMu.Lock()
		if a.geo != nil {
			home = a.geo.CountrySlug
		}
		a.geoMu.Unlock()
	}
	return discoveryTargets(peers, home, limit)
}

// parseCatalogArchive walks the repository archive. Every markdown file is one
// country; a heading of the second level or deeper names the city.
func parseCatalogArchive(raw []byte) []CatalogPeer {
	archive, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return nil
	}
	var out []CatalogPeer
	for _, file := range archive.File {
		if !strings.HasSuffix(strings.ToLower(file.Name), ".md") {
			continue
		}
		name := strings.ReplaceAll(file.Name, "\\", "/")
		segments := splitPath(name)
		// Expect at least <root>/<continent>/<country>.md.
		if len(segments) < 3 {
			continue
		}
		continent := strings.ToLower(segments[len(segments)-2])
		if continent == "other" {
			continue
		}
		slug := strings.TrimSuffix(strings.ToLower(segments[len(segments)-1]), ".md")
		if slug == "" || slug == "readme" {
			continue
		}
		reader, err := file.Open()
		if err != nil {
			continue
		}
		content, err := io.ReadAll(io.LimitReader(reader, 1<<20))
		reader.Close()
		if err != nil {
			continue
		}
		out = append(out, parseCountryMarkdown(string(content), slug)...)
	}
	// One entry per URI: the list has been known to repeat a server.
	seen := map[string]bool{}
	unique := make([]CatalogPeer, 0, len(out))
	for _, peer := range out {
		if seen[peer.URI] {
			continue
		}
		seen[peer.URI] = true
		unique = append(unique, peer)
	}
	return unique
}

func splitPath(name string) []string {
	parts := strings.Split(name, "/")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func parseCountryMarkdown(text string, slug string) []CatalogPeer {
	var out []CatalogPeer
	city := ""
	for _, rawLine := range strings.Split(text, "\n") {
		line := strings.TrimRight(rawLine, "\r")
		if strings.HasPrefix(line, "#") {
			level := strings.IndexFunc(line, func(r rune) bool { return r != '#' })
			title := strings.TrimSpace(strings.TrimLeft(line, "#"))
			if level >= 2 {
				city = cleanCity(title)
			}
			continue
		}
		for _, match := range catalogPeerPattern.FindAllStringSubmatch(line, -1) {
			uri := strings.TrimSpace(match[1])
			if !isUsablePeer(uri) {
				continue
			}
			parsed, err := url.Parse(uri)
			if err != nil {
				continue
			}
			port := 0
			if parsed.Port() != "" {
				port = atoiDefault(parsed.Port(), 0)
			}
			out = append(out, CatalogPeer{
				URI:         uri,
				Host:        strings.ToLower(parsed.Hostname()),
				Country:     slug,
				CountryName: countryName(slug),
				Flag:        countryFlag(slug),
				City:        city,
				Scheme:      parsed.Scheme,
				Port:        port,
			})
		}
	}
	return out
}

// cleanCity drops the note some headings carry after a comma or a dash.
func cleanCity(title string) string {
	value := title
	for _, separator := range []string{",", " - ", " (", "/"} {
		if index := strings.Index(value, separator); index > 0 {
			value = value[:index]
		}
	}
	return strings.TrimSpace(value)
}

// Geo returns the cached location, asking the service when the cache is empty
// or older than ten minutes. The window uses it for the discovery card.
func (a *App) Geo() geoLocation {
	a.geoMu.Lock()
	cached := a.geo
	fresh := a.geo != nil && time.Since(a.geoAt) < 10*time.Minute
	a.geoMu.Unlock()
	if fresh {
		return *cached
	}
	location, ok := lookupGeo()
	if !ok {
		if cached != nil {
			return *cached
		}
		return geoLocation{}
	}
	a.geoMu.Lock()
	a.geo = &location
	a.geoAt = time.Now()
	a.geoMu.Unlock()
	return location
}

// SetCountry stores the country the peer list is ranked around.
func (a *App) SetCountry(slug string) error {
	slug = strings.ToLower(strings.TrimSpace(slug))
	if slug != "" {
		if _, ok := countryBySlug(slug); !ok {
			return errors.New("unknown country")
		}
	}
	a.mu.Lock()
	a.cfg.CountrySlug = slug
	cfg := a.cfg
	a.mu.Unlock()
	return cfg.save()
}

// CatalogCountries lists the countries present in the catalogue for the filter.
func (a *App) CatalogCountries() []countryCount {
	a.catalogMu.Lock()
	cached := a.catalog
	a.catalogMu.Unlock()
	return countryCountsOf(cached)
}
