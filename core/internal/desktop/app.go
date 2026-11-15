package desktop

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/MrKsey/y-node-desktop/core/internal/yggnode"
)

// Version is the desktop app version, stamped by the build script.
var Version = "dev"

// State is what the window reads. It is a snapshot, not a live object.
type State struct {
	Running      bool   `json:"running"`
	Address      string `json:"address"`
	Subnet       string `json:"subnet"`
	PublicKey    string `json:"publicKey"`
	PeersUp      int    `json:"peersUp"`
	PeersTotal   int    `json:"peersTotal"`
	RxBytes      uint64 `json:"rxBytes"`
	TxBytes      uint64 `json:"txBytes"`
	OpenConns    int64  `json:"openConnections"`
	TotalConns   uint64 `json:"totalConnections"`
	ExitEnabled  bool   `json:"exitEnabled"`
	ExitName     string `json:"exitName"`
	ExitState    string `json:"exitState"`
	ExitDNS      string `json:"exitDns"`
	ProxyHTTP    string `json:"proxyHttp"`
	ProxySOCKS   string `json:"proxySocks"`
	SystemProxy  bool   `json:"systemProxy"`
	SystemAddr   string `json:"systemProxyAddress"`
	LastError    string `json:"lastError"`
	Version      string `json:"version"`
	Platform     string `json:"platform"`
	UptimeSecond int64  `json:"uptimeSeconds"`
	YggVersion   string `json:"yggVersion"`
}

// App owns the node, the proxy and the persisted configuration.
type App struct {
	mu       sync.Mutex
	cfg      Config
	node     *yggnode.Node
	proxy    *Proxy
	logs     *LogBuffer
	stats    Stats
	running  bool
	started  time.Time
	lastErr  string
	exitName string
	exitDNS  string
	exitStat string

	sysProxySet bool
	done        chan struct{}
	refreshDone chan struct{}
}

// New loads the configuration and prepares a stopped node.
func New() (*App, error) {
	cfg, err := loadConfig()
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(cfg.PrivateKey) == "" {
		key, err := generateKey()
		if err != nil {
			return nil, err
		}
		cfg.PrivateKey = key
		if err := cfg.save(); err != nil {
			return nil, err
		}
	}
	a := &App{
		cfg:  cfg,
		logs: NewLogBuffer(600),
		node: yggnode.NewNode(),
		done: make(chan struct{}),
	}
	a.node.SetLogger(a.logs)
	// A core that was killed while the system proxy was on leaves the operating
	// system pointing at a port that is no longer open.
	recoverSystemProxy(cfg.Bind, cfg.HTTPPort)
	return a, nil
}

func generateKey() (string, error) {
	raw := yggnode.GenerateKey()
	var payload struct {
		PrivateKey string `json:"privateKey"`
		Error      string `json:"error"`
	}
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		return "", err
	}
	if payload.PrivateKey == "" {
		return "", fmt.Errorf("could not generate the identity: %s", payload.Error)
	}
	return payload.PrivateKey, nil
}

// Logs returns the in-memory log.
func (a *App) Logs() []LogLine { return a.logs.List() }

// Config returns a copy of the current configuration.
func (a *App) Config() Config {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.cfg
}

// SaveConfig replaces the configuration and applies the parts that can change
// while the tunnel is up.
func (a *App) SaveConfig(next Config) error {
	next.normalise()
	a.mu.Lock()
	previous := a.cfg
	a.cfg = next
	running := a.running
	a.mu.Unlock()

	if err := next.save(); err != nil {
		return err
	}
	if !running {
		return nil
	}
	if previous.HTTPPort != next.HTTPPort || previous.SocksPort != next.SocksPort || previous.Bind != next.Bind {
		return errors.New("the proxy ports change on the next connect")
	}
	if previous.exitJSON() != next.exitJSON() {
		if err := a.node.SetDesktopExitConfig(next.exitJSON()); err != nil {
			a.logs.Warnf("exit configuration: %v", err)
			return err
		}
	}
	if previous.SystemProxy != next.SystemProxy {
		if err := a.applySystemProxy(next.SystemProxy); err != nil {
			return err
		}
	}
	return nil
}

// Connect starts the node and the local proxy.
func (a *App) Connect() error {
	a.mu.Lock()
	if a.running {
		a.mu.Unlock()
		return nil
	}
	cfg := a.cfg
	a.mu.Unlock()

	if len(cfg.peerList()) == 0 {
		return errors.New("no peers configured: add a peer or press Auto")
	}
	payload, _ := json.Marshal(map[string]any{
		"privateKey": cfg.PrivateKey,
		"peers":      cfg.peerList(),
		"mtu":        cfg.MTU,
		"platform":   runtime.GOOS,
	})
	if err := a.node.Start(string(payload)); err != nil {
		a.mu.Lock()
		a.lastErr = err.Error()
		a.mu.Unlock()
		return err
	}
	// The desktop app has no TUN, but the node still has to be read: the
	// packets of its own DNS and SOCKS5 connections arrive through the same
	// tunnel and are routed to the internal stack by Recv.
	a.node.StartDesktopPump()
	if err := a.node.SetDesktopExitConfig(cfg.exitJSON()); err != nil {
		a.node.Stop()
		return err
	}
	proxy := NewProxy(a.node.DesktopDial, a.logs, &a.stats)
	if err := proxy.Start(cfg.Bind, cfg.HTTPPort, cfg.SocksPort); err != nil {
		a.node.Stop()
		a.mu.Lock()
		a.lastErr = err.Error()
		a.mu.Unlock()
		return err
	}

	a.mu.Lock()
	a.proxy = proxy
	a.running = true
	a.started = time.Now()
	a.lastErr = ""
	a.exitName = ""
	a.exitDNS = ""
	a.exitStat = ""
	systemProxy := a.cfg.SystemProxy
	a.mu.Unlock()

	if systemProxy {
		if err := a.applySystemProxy(true); err != nil {
			a.logs.Warnf("system proxy: %v", err)
		}
	}

	close(a.done)
	a.done = make(chan struct{})
	a.refreshDone = make(chan struct{})
	go a.refreshLoop(a.done, a.refreshDone)
	a.refreshState()
	a.logs.Infof("connected: %s", a.node.GetAddress())
	return nil
}

// Disconnect stops the proxy and the node.
func (a *App) Disconnect() error {
	a.mu.Lock()
	if !a.running {
		a.mu.Unlock()
		return nil
	}
	proxy := a.proxy
	wasSystemProxy := a.sysProxySet
	a.running = false
	a.proxy = nil
	done := a.done
	refreshDone := a.refreshDone
	a.mu.Unlock()

	close(done)
	if refreshDone != nil {
		<-refreshDone
	}
	if wasSystemProxy {
		if err := setSystemProxy(false, "", 0); err != nil {
			a.logs.Warnf("system proxy: %v", err)
		}
	}
	if proxy != nil {
		proxy.Stop()
	}
	a.node.Stop()
	a.mu.Lock()
	a.sysProxySet = false
	a.mu.Unlock()
	a.logs.Infof("disconnected")
	return nil
}

// Shutdown stops everything; used when the process exits.
func (a *App) Shutdown() {
	_ = a.Disconnect()
}

// applySystemProxy writes or clears the per-user system proxy.
func (a *App) applySystemProxy(enable bool) error {
	a.mu.Lock()
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if !running {
		return errors.New("the tunnel is not running")
	}
	if err := setSystemProxy(enable, cfg.Bind, cfg.HTTPPort); err != nil {
		return err
	}
	a.mu.Lock()
	a.sysProxySet = enable
	a.mu.Unlock()
	if enable {
		a.logs.Infof("system proxy: %s:%d", cfg.Bind, cfg.HTTPPort)
	} else {
		a.logs.Infof("system proxy cleared")
	}
	return nil
}

// SetSystemProxy is the switch in the window.
func (a *App) SetSystemProxy(enable bool) error {
	a.mu.Lock()
	a.cfg.SystemProxy = enable
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	if !running {
		return nil
	}
	return a.applySystemProxy(enable)
}

// State returns the current snapshot.
func (a *App) State() State {
	a.mu.Lock()
	cfg := a.cfg
	running := a.running
	started := a.started
	lastErr := a.lastErr
	exitName := a.exitName
	exitDNS := a.exitDNS
	exitStat := a.exitStat
	a.mu.Unlock()

	state := State{
		Running:     running,
		ExitEnabled: cfg.ExitEnabled && len(cfg.ExitProfiles) > 0,
		ExitName:    exitName,
		ExitState:   exitStat,
		ExitDNS:     exitDNS,
		ProxyHTTP:   fmt.Sprintf("%s:%d", cfg.Bind, cfg.HTTPPort),
		ProxySOCKS:  fmt.Sprintf("%s:%d", cfg.Bind, cfg.SocksPort),
		SystemProxy: cfg.SystemProxy,
		LastError:   lastErr,
		Version:     Version,
		Platform:    runtime.GOOS,
		YggVersion:  yggnode.GetVersion(),
	}
	if enabled, addr := systemProxyState(); enabled {
		state.SystemProxy = true
		state.SystemAddr = addr
	}
	state.RxBytes = a.stats.Up.Load()
	state.TxBytes = a.stats.Down.Load()
	state.OpenConns = a.stats.Open.Load()
	state.TotalConns = a.stats.TotalOpen.Load()
	if running {
		state.Address = a.node.GetAddress()
		state.Subnet = a.node.GetSubnet()
		state.PublicKey = a.node.GetPublicKey()
		state.UptimeSecond = int64(time.Since(started).Seconds())
		var peers []struct {
			Up bool `json:"up"`
		}
		if err := json.Unmarshal([]byte(a.node.GetPeersJSON()), &peers); err == nil {
			state.PeersTotal = len(peers)
			for _, peer := range peers {
				if peer.Up {
					state.PeersUp++
				}
			}
		}
	} else {
		state.Address, state.Subnet, state.PublicKey = a.Identity()
	}
	return state
}

// Identity returns the address, subnet and public key of the stored identity.
func (a *App) Identity() (address, subnet, publicKey string) {
	a.mu.Lock()
	key := a.cfg.PrivateKey
	a.mu.Unlock()
	raw := yggnode.SummaryForPrivateKey(key)
	var payload struct {
		Address   string `json:"address"`
		Subnet    string `json:"subnet"`
		PublicKey string `json:"publicKey"`
	}
	_ = json.Unmarshal([]byte(raw), &payload)
	return payload.Address, payload.Subnet, payload.PublicKey
}

// Peers returns the live peer list.
func (a *App) Peers() []yggnode.PeerStatus {
	var out []yggnode.PeerStatus
	_ = json.Unmarshal([]byte(a.node.GetPeersJSON()), &out)
	return out
}

// AddPeer stores a peer and applies it to the running node.
func (a *App) AddPeer(uri string) error {
	uri = strings.TrimSpace(uri)
	if !isUsablePeer(uri) {
		return errors.New("this is not a Yggdrasil peer URI")
	}
	a.mu.Lock()
	for _, existing := range a.cfg.Peers {
		if existing == uri {
			a.mu.Unlock()
			return nil
		}
	}
	a.cfg.Peers = append(a.cfg.Peers, uri)
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	if running {
		payload, _ := json.Marshal(cfg.peerList())
		if err := a.node.SetPeers(string(payload)); err != nil {
			return err
		}
	}
	return nil
}

// RemovePeer drops a peer from the configuration and the running node.
func (a *App) RemovePeer(uri string) error {
	a.mu.Lock()
	next := make([]string, 0, len(a.cfg.Peers))
	for _, existing := range a.cfg.Peers {
		if existing != uri {
			next = append(next, existing)
		}
	}
	a.cfg.Peers = next
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	if running {
		payload, _ := json.Marshal(cfg.peerList())
		if err := a.node.SetPeers(string(payload)); err != nil {
			return err
		}
	}
	return nil
}

// ExitProfiles returns the configured exit nodes.
func (a *App) ExitProfiles() ([]ExitProfile, string, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]ExitProfile(nil), a.cfg.ExitProfiles...), a.cfg.ExitActiveID, a.cfg.ExitEnabled
}

// AddExitLink imports a yggnode://exit link and makes it active.
func (a *App) AddExitLink(link string) (ExitProfile, error) {
	profile, invite, err := ParseExitLink(link)
	if err != nil {
		return ExitProfile{}, err
	}
	a.mu.Lock()
	replaced := false
	for index, existing := range a.cfg.ExitProfiles {
		if existing.ID == profile.ID {
			profile.Token = existing.Token
			a.cfg.ExitProfiles[index] = profile
			replaced = true
			break
		}
	}
	if !replaced {
		a.cfg.ExitProfiles = append(a.cfg.ExitProfiles, profile)
	}
	a.cfg.ExitActiveID = profile.ID
	a.cfg.ExitEnabled = true
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return ExitProfile{}, err
	}

	if invite != "" {
		result := a.node.RegisterExit(profile.ID, invite, deviceName(), "Y-Node Desktop "+Version)
		var payload struct {
			OK      bool   `json:"ok"`
			Token   string `json:"token"`
			DNSAddr string `json:"dnsAddress"`
			DNSPort int    `json:"dnsPort"`
			Error   string `json:"error"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal([]byte(result), &payload); err == nil {
			if payload.OK {
				a.mu.Lock()
				for index, existing := range a.cfg.ExitProfiles {
					if existing.ID != profile.ID {
						continue
					}
					if payload.Token != "" {
						a.cfg.ExitProfiles[index].Token = payload.Token
						profile.Token = payload.Token
					}
					if payload.DNSAddr != "" {
						a.cfg.ExitProfiles[index].DNS = payload.DNSAddr
						a.cfg.ExitProfiles[index].DNSPort = payload.DNSPort
						profile.DNS = payload.DNSAddr
						profile.DNSPort = payload.DNSPort
					}
				}
				cfg = a.cfg
				a.mu.Unlock()
				_ = cfg.save()
				a.logs.Infof("registered with exit %s", profile.Name)
			} else {
				a.logs.Warnf("exit registration: %s %s", payload.Error, payload.Message)
			}
		}
	}

	a.applyExitConfig()
	return profile, nil
}

func deviceName() string {
	host, err := os.Hostname()
	if err != nil || host == "" {
		return "Desktop"
	}
	return host
}

// RemoveExit drops one profile.
func (a *App) RemoveExit(id string) error {
	a.mu.Lock()
	next := make([]ExitProfile, 0, len(a.cfg.ExitProfiles))
	for _, profile := range a.cfg.ExitProfiles {
		if profile.ID != id {
			next = append(next, profile)
		}
	}
	a.cfg.ExitProfiles = next
	if a.cfg.ExitActiveID == id {
		a.cfg.ExitActiveID = ""
		if len(next) > 0 {
			a.cfg.ExitActiveID = next[0].ID
		}
	}
	if len(next) == 0 {
		a.cfg.ExitEnabled = false
	}
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	a.applyExitConfig()
	return nil
}

// SetExitActive selects the exit node.
func (a *App) SetExitActive(id string) error {
	a.mu.Lock()
	found := false
	for _, profile := range a.cfg.ExitProfiles {
		if profile.ID == id {
			found = true
			break
		}
	}
	if !found {
		a.mu.Unlock()
		return errors.New("unknown exit profile")
	}
	a.cfg.ExitActiveID = id
	a.cfg.ExitEnabled = true
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	a.applyExitConfig()
	return nil
}

// SetExitEnabled turns public traffic through the exit on or off.
func (a *App) SetExitEnabled(enable bool) error {
	a.mu.Lock()
	a.cfg.ExitEnabled = enable && len(a.cfg.ExitProfiles) > 0
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	a.applyExitConfig()
	return nil
}

// applyExitConfig pushes the profile list to the bridge and keeps the pinned
// peer of the selected node in the peer list.
func (a *App) applyExitConfig() {
	a.mu.Lock()
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if !running {
		return
	}
	if err := a.node.SetDesktopExitConfig(cfg.exitJSON()); err != nil {
		a.logs.Warnf("exit configuration: %v", err)
		return
	}
	payload, _ := json.Marshal(cfg.peerList())
	if err := a.node.SetPeers(string(payload)); err != nil {
		a.logs.Warnf("exit peer: %v", err)
	}
}

// CheckExit asks every profile's status API whether this client is allowed.
func (a *App) CheckExit() string {
	a.mu.Lock()
	running := a.running
	a.mu.Unlock()
	if !running {
		return `{"enabled":false,"state":"off","profiles":[]}`
	}
	return a.node.CheckExitProfiles(9000)
}

// ExitStatus returns the last exit state as JSON.
func (a *App) ExitStatus() string {
	return a.node.GetExitStatusJSON()
}

// refreshLoop keeps the snapshot fresh and polls the exit health.
func (a *App) refreshLoop(done <-chan struct{}, finished chan<- struct{}) {
	defer close(finished)
	ticker := time.NewTicker(2 * time.Second)
	health := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	defer health.Stop()
	for {
		select {
		case <-done:
			return
		case <-ticker.C:
			a.refreshState()
		case <-health.C:
			a.mu.Lock()
			enabled := a.cfg.ExitEnabled && len(a.cfg.ExitProfiles) > 0
			a.mu.Unlock()
			if enabled {
				a.node.CheckExitProfiles(9000)
				a.refreshState()
			}
		}
	}
}

// refreshState reads the node status, remembers a learned token and picks up the
// resolver the exit publishes.
func (a *App) refreshState() {
	if !a.node.IsRunning() {
		return
	}
	raw := a.node.GetExitStatusJSON()
	var status struct {
		State    string `json:"state"`
		ActiveID string `json:"activeId"`
		Profiles []struct {
			ID         string `json:"id"`
			Name       string `json:"name"`
			Token      string `json:"token"`
			DNSAddress string `json:"dnsAddress"`
			DNSPort    int    `json:"dnsPort"`
			DNSKnown   bool   `json:"dnsKnown"`
		} `json:"profiles"`
	}
	if err := json.Unmarshal([]byte(raw), &status); err != nil {
		return
	}
	name := ""
	dns := ""
	activeID := status.ActiveID
	for _, profile := range status.Profiles {
		if activeID == "" || profile.ID == activeID {
			name = profile.Name
			if profile.DNSKnown && profile.DNSAddress != "" {
				dns = profile.DNSAddress
				if profile.DNSPort != 0 && profile.DNSPort != 53 {
					dns = net.JoinHostPort(profile.DNSAddress, fmt.Sprint(profile.DNSPort))
				}
			}
			break
		}
	}
	a.mu.Lock()
	a.exitName = name
	a.exitStat = status.State
	changed := false
	for _, item := range status.Profiles {
		for index, profile := range a.cfg.ExitProfiles {
			if profile.ID != item.ID {
				continue
			}
			if item.Token != "" && item.Token != profile.Token {
				a.cfg.ExitProfiles[index].Token = item.Token
				changed = true
			}
			if item.DNSKnown && item.DNSAddress != "" && profile.DNS != item.DNSAddress {
				a.cfg.ExitProfiles[index].DNS = item.DNSAddress
				a.cfg.ExitProfiles[index].DNSPort = item.DNSPort
				changed = true
			}
		}
	}
	previousDNS := a.exitDNS
	a.exitDNS = dns
	if changed {
		cfg := a.cfg
		_ = cfg.save()
	}
	dnsChanged := dns != "" && dns != previousDNS && len(a.cfg.ExitDNS) > 0 && a.cfg.ExitDNS[0] != dns
	if dnsChanged {
		a.cfg.ExitDNS = []string{dns}
		cfg := a.cfg
		_ = cfg.save()
		a.mu.Unlock()
		a.logs.Infof("exit resolver: %s", dns)
		if err := a.node.SetDesktopExitConfig(cfg.exitJSON()); err != nil {
			a.logs.Warnf("exit configuration: %v", err)
		}
		return
	}
	a.mu.Unlock()
}
