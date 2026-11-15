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
	Peer      string `json:"peer,omitempty"`
	DNS       string `json:"dns,omitempty"`
	DNSPort   int    `json:"dnsPort,omitempty"`
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

	SystemProxy bool `json:"systemProxy"`
	AutoConnect bool `json:"autoConnect"`
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
		YggDNS: []string{
			"308:84:68:55::",
			"308:25:40:bd::",
			"215:1e33:6417:d636:c807:6985:4f4e:fda0",
			"202:cbff:6f7f:fa95:c6e9:3768:a96e:d1c8",
		},
		SystemDNS: []string{"9.9.9.9", "1.1.1.1"},
		LocalDNS:  true,
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
		return DefaultConfig(), nil
	}
	if err != nil {
		return Config{}, err
	}
	cfg := DefaultConfig()
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return Config{}, fmt.Errorf("config.json: %w", err)
	}
	cfg.normalise()
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
	if len(c.SystemDNS) == 0 {
		c.SystemDNS = DefaultConfig().SystemDNS
	}
	if c.ExitActiveID == "" && len(c.ExitProfiles) > 0 {
		c.ExitActiveID = c.ExitProfiles[0].ID
	}
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
	payload := map[string]any{
		"enabled":        c.ExitEnabled && len(profiles) > 0,
		"profiles":       profiles,
		"activeId":       c.ExitActiveID,
		"fallbackDirect": c.ExitFallbackDirect,
		"dns":            c.ExitDNS,
		"systemDns":      c.SystemDNS,
		"yggDns":         c.YggDNS,
		"localDns":       c.LocalDNS,
		"udp":            true,
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
