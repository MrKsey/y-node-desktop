package desktop

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/MrKsey/y-node-desktop/core/internal/yggnode"
)

// ExitProfile is one exit node known to the desktop app. It carries the fields
// the invite link publishes that the bridge does not need: the pinned peer and
// the resolver address.
type ExitProfile struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Address   string `json:"address"`
	SocksPort int    `json:"socksPort"`
	APIPort   int    `json:"apiPort"`
	Token     string `json:"token,omitempty"`
	// Invite is the one-time secret from the yggnode://exit link. It is kept
	// until the registration succeeds, so a link imported before the tunnel is
	// up can be redeemed on the next connect instead of leaving the client
	// outside the allowlist for good.
	Invite string `json:"invite,omitempty"`
	// Registered is set when the exit accepted this client. A profile with a
	// token does not need the invite any more.
	Registered bool   `json:"registered,omitempty"`
	Peer       string `json:"peer,omitempty"`
	DNS        string `json:"dns,omitempty"`
	DNSPort    int    `json:"dnsPort,omitempty"`
}

// ServiceEntry is one in-network site in the Services page. The built-in list
// lives in the core with the entries the user added, so the order and the
// built-in flag survive a restart exactly like the Android address book.
type ServiceEntry struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	URL         string `json:"url"`
	Description string `json:"description,omitempty"`
	BuiltIn     bool   `json:"builtIn,omitempty"`
}

// ProbeEntry is one row of the last latency test. The list is stored, so the
// Peers page shows the discovery results after a restart, like the Android
// client keeps its probe session.
type ProbeEntry struct {
	URI       string  `json:"uri"`
	Up        bool    `json:"up"`
	LatencyMs float64 `json:"latencyMs,omitempty"`
	Error     string  `json:"error,omitempty"`
}

// Config is the persisted state of the desktop core.
type Config struct {
	PrivateKey string   `json:"privateKey"`
	Peers      []string `json:"peers"`
	MTU        int      `json:"mtu"`

	Bind      string `json:"bind"`
	HTTPPort  int    `json:"httpPort"`
	SocksPort int    `json:"socksPort"`

	ExitEnabled        bool          `json:"exitEnabled"`
	ExitActiveID       string        `json:"exitActiveId"`
	ExitProfiles       []ExitProfile `json:"exitProfiles"`
	ExitFallbackDirect bool          `json:"exitFallbackDirect"`
	ExitDNS            []string      `json:"exitDns"`
	YggDNS             []string      `json:"yggDns"`
	SystemDNS          []string      `json:"systemDns"`
	LocalDNS           bool          `json:"localDns"`
	// DNSMode selects how names are resolved: "yggdrasil" (the default, .ygg
	// names through the in-network resolvers), "system" (the resolver of the
	// operating system) or "custom" (the list in YggDNS).
	DNSMode string `json:"dnsMode"`
	// ExitDNSEnabled uses the resolver the exit node publishes for ordinary
	// names. With it off they go to the system resolvers.
	ExitDNSEnabled bool `json:"exitDnsEnabled"`
	// ExitUDP relays public UDP (DNS, QUIC) through the exit.
	ExitUDP bool `json:"exitUdp"`
	// IPv6 selects how outbound names are resolved: "auto", "prefer" or "off".
	IPv6 string `json:"ipv6"`
	// ExitLabelEnabled sends the device name (or ExitLabel) to the exit node
	// during registration, the way the Android client's "My name on exit node"
	// switch does. The exit shows it in its client list.
	ExitLabelEnabled bool   `json:"exitLabelEnabled"`
	ExitLabel        string `json:"exitLabel"`

	// PeerCount is how many public peers the app keeps configured, the way the
	// Android client does. PeerAutoReplace swaps a peer that stays down for
	// PeerDeadTimeout with a faster candidate.
	PeerCount         int    `json:"peerCount"`
	PeerAutoReplace   bool   `json:"peerAutoReplace"`
	PeerDeadTimeout   string `json:"peerDeadTimeout"`
	PeerCheckInterval string `json:"peerCheckInterval"`

	// Pool is the replacement pool: live nodes that are not in the tunnel and
	// take the place of a peer that drops.
	Pool []string `json:"pool,omitempty"`
	// CountrySlug is the country the public list is ranked around. Empty means
	// "detect automatically".
	CountrySlug string `json:"countrySlug,omitempty"`

	SystemProxy bool `json:"systemProxy"`
	AutoConnect bool `json:"autoConnect"`

	// Theme is the window colour scheme: "auto", "light" or "dark".
	Theme string `json:"theme"`
	// CloseToTray hides the window instead of quitting. A running tunnel keeps
	// the application in the tray even when this switch is off.
	CloseToTray bool `json:"closeToTray"`
	// MinimizeToTray hides the window when it is minimised.
	MinimizeToTray bool `json:"minimizeToTray"`

	// UpdateCheck asks GitHub for a newer release when the window starts.
	// UpdateNotified is the version the user was already told about, so the
	// same release is not announced on every launch.
	UpdateCheck    bool   `json:"updateCheck"`
	UpdateNotified string `json:"updateNotified,omitempty"`

	// Services are the in-network sites of the Services page: the built-in
	// catalogue and the entries the user added, in one ordered list.
	Services []ServiceEntry `json:"services,omitempty"`
	// HiddenServices are the built-in entries the user deleted from the
	// Services page. The catalogue is merged on every read, so a removed
	// default has to be remembered: without this list it would come back on
	// the next start.
	HiddenServices []string `json:"hiddenServices,omitempty"`

	// LastProbe is the result of the last latency test, kept so the Peers page
	// still shows the discovery rows after a restart.
	LastProbe []ProbeEntry `json:"lastProbe,omitempty"`
	// LoggingDisabled stops the in-memory log. The switch on the Logs page owns
	// it; the default is a written log.
	LoggingDisabled bool `json:"loggingDisabled,omitempty"`

	// pendingSave marks a file that normalise() completed: the built-in
	// services are added in memory, and the core writes them back so the
	// Services page of every build reads the same catalogue from the file.
	pendingSave bool
}

// DefaultConfig is what a fresh install starts with. The DNS servers are the
// public in-network resolvers from the Yggdrasil wiki; they only answer while
// the node is up.
func DefaultConfig() Config {
	return Config{
		Peers:              nil,
		MTU:                1280,
		Bind:               "127.0.0.1",
		HTTPPort:           7890,
		SocksPort:          7891,
		ExitFallbackDirect: true,
		// A fresh install starts with the two resolvers of the Android client's
		// default table: Frankfurt and Amsterdam. The rest of the wiki list is
		// offered under "Available servers".
		YggDNS: []string{
			"308:84:68:55::",
			"308:62:45:62::",
		},
		// The local resolver list is empty by default: the operating system
		// already knows the resolvers of the real network, which is what the
		// Android client means by "Automatic (real network)".
		SystemDNS: nil,
		LocalDNS:  true,
		DNSMode:   "yggdrasil",
		// The public resolvers the exit queries over its relay. The Android
		// client defaults to the same pair; the exit's own published resolver
		// is a separate switch and is not mixed into this list.
		ExitDNS: []string{"1.1.1.1", "9.9.9.9"},
		// An exit node that publishes a resolver is the closest one to the
		// traffic, so it is used by default, like the "DNS exit node" switch of
		// the Android client.
		ExitDNSEnabled:    true,
		ExitUDP:           true,
		IPv6:              "auto",
		PeerCount:         3,
		PeerAutoReplace:   true,
		PeerDeadTimeout:   "90s",
		PeerCheckInterval: "30s",
		Theme:             "auto",
		// The desktop client carries the traffic of this computer, so a fresh
		// install points the system proxy at it from the first connect.
		SystemProxy: true,
		// A desktop app that keeps a tunnel open should not disappear because
		// the window was closed: the tray is the default exit.
		CloseToTray: true,
		// The catalogue of the Services page is part of the program, like the
		// address book of the Android client: a fresh install starts with the
		// eight in-network sites even before a configuration file exists.
		Services: builtInServices(),
	}
}

// ConfigDir returns the per-user directory of the desktop app.
func ConfigDir() (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(base, "Y-Node")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}

func configPath() (string, error) {
	dir, err := ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "config.json"), nil
}

func loadConfig() (Config, error) {
	path, err := configPath()
	if err != nil {
		return Config{}, err
	}
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		// The very first start has no file at all. DefaultConfig already
		// carries the built-in catalogue, and normalise() keeps the rest of the
		// defaults consistent with a file that went through the same path.
		cfg := DefaultConfig()
		cfg.normalise()
		cfg.pendingSave = true
		return cfg, nil
	}
	if err != nil {
		return Config{}, err
	}
	cfg := DefaultConfig()
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return Config{}, fmt.Errorf("config.json: %w", err)
	}
	// A file written by a build without the built-in catalogue has no
	// "services" key at all: the page would still show the entries from
	// memory, but a window that reads the file directly (or a downgrade) sees
	// an empty list. The completed configuration is written back once, so the
	// catalogue is part of the file from the first start.
	var stored map[string]json.RawMessage
	_ = json.Unmarshal(raw, &stored)
	_, hasServices := stored["services"]
	before := len(cfg.Services)
	servicesBefore, _ := json.Marshal(cfg.Services)
	hiddenBefore, _ := json.Marshal(cfg.HiddenServices)
	cfg.normalise()
	servicesAfter, _ := json.Marshal(cfg.Services)
	hiddenAfter, _ := json.Marshal(cfg.HiddenServices)
	// normalise() also repairs a catalogue entry the user pointed at another
	// address; that change has to reach the file, or the badge would be
	// recomputed on every start.
	if !hasServices || len(cfg.Services) != before ||
		string(servicesBefore) != string(servicesAfter) ||
		string(hiddenBefore) != string(hiddenAfter) {
		cfg.pendingSave = true
	}
	return cfg, nil
}

func (c *Config) normalise() {
	if c.MTU < 1280 {
		c.MTU = 1280
	}
	if strings.TrimSpace(c.Bind) == "" {
		c.Bind = "127.0.0.1"
	}
	if c.HTTPPort < 1 || c.HTTPPort > 65535 {
		c.HTTPPort = 7890
	}
	if c.SocksPort < 1 || c.SocksPort > 65535 {
		c.SocksPort = 7891
	}
	if len(c.YggDNS) == 0 {
		c.YggDNS = DefaultConfig().YggDNS
	}
	if len(c.ExitDNS) == 0 {
		// The exit queries its public resolvers over the relay. An empty list
		// in an older file means "not configured yet", not "no DNS".
		c.ExitDNS = DefaultConfig().ExitDNS
	}
	// Older builds wrote the resolver the exit publishes into the public list.
	// That address is a Yggdrasil one: it belongs to the in-network list and is
	// owned by the "DNS exit node" switch, not by the Exit DNS form.
	public := make([]string, 0, len(c.ExitDNS))
	for _, server := range c.ExitDNS {
		if isYggdrasilAddress(server) {
			continue
		}
		public = append(public, server)
	}
	if len(public) == 0 {
		public = DefaultConfig().ExitDNS
	}
	c.ExitDNS = public
	// The old default was a fixed pair of public resolvers. A file that still
	// carries exactly that pair never had a choice made for it: the local list
	// is empty by default and means "the resolvers of the real network".
	if len(c.SystemDNS) == 2 && c.SystemDNS[0] == "9.9.9.9" && c.SystemDNS[1] == "1.1.1.1" {
		c.SystemDNS = nil
	}
	if c.ExitActiveID == "" && len(c.ExitProfiles) > 0 {
		c.ExitActiveID = c.ExitProfiles[0].ID
	}
	switch strings.ToLower(strings.TrimSpace(c.Theme)) {
	case "light", "dark":
		c.Theme = strings.ToLower(strings.TrimSpace(c.Theme))
	default:
		c.Theme = "auto"
	}
	switch strings.ToLower(strings.TrimSpace(c.DNSMode)) {
	case "system", "custom":
		c.DNSMode = strings.ToLower(strings.TrimSpace(c.DNSMode))
	default:
		c.DNSMode = "yggdrasil"
	}
	switch strings.ToLower(strings.TrimSpace(c.IPv6)) {
	case "prefer", "off":
		c.IPv6 = strings.ToLower(strings.TrimSpace(c.IPv6))
	default:
		c.IPv6 = "auto"
	}
	if c.PeerCount < 1 || c.PeerCount > 20 {
		c.PeerCount = 3
	}
	if _, err := time.ParseDuration(strings.TrimSpace(c.PeerDeadTimeout)); err != nil {
		c.PeerDeadTimeout = "90s"
	}
	if _, err := time.ParseDuration(strings.TrimSpace(c.PeerCheckInterval)); err != nil {
		c.PeerCheckInterval = "30s"
	}
	// The exit caps the label at 32 characters; the same limit the Android
	// client enforces keeps the two clients interchangeable.
	runes := []rune(strings.TrimSpace(c.ExitLabel))
	if len(runes) > 32 {
		c.ExitLabel = string(runes[:32])
	} else {
		c.ExitLabel = string(runes)
	}
	c.Services, c.HiddenServices = demoteEditedBuiltIns(c.Services, c.HiddenServices)
	c.Services = withBuiltInServices(c.Services, c.HiddenServices)
	c.HiddenServices = uniqueStrings(c.HiddenServices)
	c.Pool = uniquePeers(c.Pool)
	c.Peers = uniquePeers(c.Peers)
}

func (c Config) save() error {
	path, err := configPath()
	if err != nil {
		return err
	}
	raw, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// exitJSON builds the configuration the bridge expects.
func (c Config) exitJSON() string {
	profiles := make([]yggnode.ExitProfile, 0, len(c.ExitProfiles))
	for _, profile := range c.ExitProfiles {
		profiles = append(profiles, yggnode.ExitProfile{
			ID:        profile.ID,
			Name:      profile.Name,
			Address:   profile.Address,
			SocksPort: profile.SocksPort,
			APIPort:   profile.APIPort,
			Token:     profile.Token,
		})
	}
	// "dns" holds the public resolvers the exit queries over its relay: the
	// ordinary servers of the Exit DNS list, never the exit's own Yggdrasil
	// resolver.
	exitDNS := c.ExitDNS
	if len(exitDNS) == 0 {
		exitDNS = DefaultConfig().ExitDNS
	}
	// The resolver the exit publishes for its clients is a Yggdrasil DNS
	// server, so it belongs to the in-network list; the "DNS exit node" switch
	// owns it.
	yggDNS := append([]string(nil), c.YggDNS...)
	if c.ExitDNSEnabled {
		if profile, ok := c.activeProfile(); ok && profile.DNS != "" {
			present := false
			for _, server := range yggDNS {
				if server == profile.DNS {
					present = true
					break
				}
			}
			if !present {
				yggDNS = append(yggDNS, profile.DNS)
			}
		}
	}
	payload := map[string]any{
		"enabled":        c.ExitEnabled && len(profiles) > 0,
		"profiles":       profiles,
		"activeId":       c.ExitActiveID,
		"fallbackDirect": c.ExitFallbackDirect,
		"dns":            exitDNS,
		"dnsMode":        c.DNSMode,
		"systemDns":      c.SystemDNS,
		"yggDns":         yggDNS,
		"localDns":       c.LocalDNS,
		"udp":            c.ExitUDP,
		"ipv6":           c.IPv6,
	}
	raw, _ := json.Marshal(payload)
	return string(raw)
}

// activeProfile returns the selected profile, falling back to the first one.
func (c Config) activeProfile() (ExitProfile, bool) {
	if len(c.ExitProfiles) == 0 {
		return ExitProfile{}, false
	}
	for _, profile := range c.ExitProfiles {
		if profile.ID == c.ExitActiveID {
			return profile, true
		}
	}
	return c.ExitProfiles[0], true
}

// peerList is the peer set the node is started with: the configured public
// peers plus the pinned peer of the active exit node.
func (c Config) peerList() []string {
	out := make([]string, 0, len(c.Peers)+1)
	seen := make(map[string]bool, len(c.Peers)+1)
	for _, uri := range c.Peers {
		uri = strings.TrimSpace(uri)
		if uri == "" || seen[uri] {
			continue
		}
		seen[uri] = true
		out = append(out, uri)
	}
	if profile, ok := c.activeProfile(); ok && c.ExitEnabled {
		uri := strings.TrimSpace(profile.Peer)
		if uri != "" && !seen[uri] {
			out = append(out, uri)
		}
	}
	return out
}

// ParseExitLink parses a yggnode://exit link printed by X-Node.
func ParseExitLink(raw string) (ExitProfile, string, error) {
	value := strings.NewReplacer("\r", "", "\n", "", "\t", "").Replace(raw)
	value = strings.TrimSpace(value)
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "yggnode" || parsed.Host != "exit" {
		return ExitProfile{}, "", errors.New("this is not a yggnode://exit link")
	}
	query := parsed.Query()
	address := strings.TrimSpace(query.Get("a"))
	if !isYggdrasilAddress(address) {
		return ExitProfile{}, "", errors.New("the link has no Yggdrasil address")
	}
	socks := atoiDefault(query.Get("p"), 1080)
	api := atoiDefault(query.Get("api"), 1080)
	if api == 0 {
		api = socks
	}
	if socks < 1 || socks > 65535 || api < 1 || api > 65535 {
		return ExitProfile{}, "", errors.New("the link has an invalid port")
	}
	name := strings.TrimSpace(query.Get("n"))
	if name == "" {
		name = address
	}
	profile := ExitProfile{
		ID:        fmt.Sprintf("%s:%d", address, socks),
		Name:      name,
		Address:   address,
		SocksPort: socks,
		APIPort:   api,
		DNSPort:   atoiDefault(query.Get("dnsport"), 53),
	}
	if peer := strings.TrimSpace(query.Get("peer")); isUsablePeer(peer) {
		profile.Peer = peer
	}
	if dns := strings.TrimSpace(query.Get("dns")); isYggdrasilAddress(dns) {
		profile.DNS = dns
	}
	return profile, strings.TrimSpace(query.Get("i")), nil
}

func atoiDefault(text string, fallback int) int {
	if value, err := strconv.Atoi(strings.TrimSpace(text)); err == nil {
		return value
	}
	return fallback
}

func isYggdrasilAddress(value string) bool {
	ip := net.ParseIP(strings.TrimSpace(value))
	if ip == nil || ip.To4() != nil {
		return false
	}
	raw := ip.To16()
	return raw != nil && raw[0]&0xFE == 0x02
}

func isUsablePeer(value string) bool {
	if value == "" {
		return false
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Host == "" || !parsed.IsAbs() {
		return false
	}
	switch parsed.Scheme {
	case "tls", "tcp", "ws", "wss", "quic":
	default:
		return false
	}
	if parsed.Port() == "" {
		return false
	}
	if ip := net.ParseIP(parsed.Hostname()); ip != nil && isYggdrasilAddress(ip.String()) {
		return false
	}
	return true
}
