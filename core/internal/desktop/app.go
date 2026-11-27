package desktop

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/MrKsey/y-node-desktop/core/internal/yggnode"
)

// Version is the desktop app version, stamped by the build script.
var Version = "dev"

// State is what the window reads. It is a snapshot, not a live object.
type State struct {
	Running     bool   `json:"running"`
	Address     string `json:"address"`
	Subnet      string `json:"subnet"`
	PublicKey   string `json:"publicKey"`
	PeersUp     int    `json:"peersUp"`
	PeersTotal  int    `json:"peersTotal"`
	RxBytes     uint64 `json:"rxBytes"`
	TxBytes     uint64 `json:"txBytes"`
	OpenConns   int64  `json:"openConnections"`
	TotalConns  uint64 `json:"totalConnections"`
	ExitEnabled bool   `json:"exitEnabled"`
	ExitInUse   bool   `json:"exitInUse"`
	ExitName    string `json:"exitName"`
	ExitState   string `json:"exitState"`
	ExitDNS     string `json:"exitDns"`
	// ExitFlag and ExitCountry place the exit server, so the tunnel screen can
	// show the flag of the node that carries the traffic.
	ExitFlag    string `json:"exitFlag"`
	ExitCountry string `json:"exitCountry"`
	ExitCity    string `json:"exitCity"`
	// LatencyMs is the best round-trip time among the live public peers. The
	// tunnel screen shows it where the Android client shows its latency.
	LatencyMs    float64 `json:"latencyMs"`
	ProxyHTTP    string  `json:"proxyHttp"`
	ProxySOCKS   string  `json:"proxySocks"`
	SystemProxy  bool    `json:"systemProxy"`
	SystemAddr   string  `json:"systemProxyAddress"`
	LastError    string  `json:"lastError"`
	Version      string  `json:"version"`
	Platform     string  `json:"platform"`
	UptimeSecond int64   `json:"uptimeSeconds"`
	YggVersion   string  `json:"yggVersion"`
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

	// sessionCtx belongs to one connected session. Disconnect cancels it, so an
	// exit health check or a peer probe that is already running stops talking to
	// the network instead of finishing after the tunnel is down.
	sessionCtx    context.Context
	sessionCancel context.CancelFunc

	// lastRegisterAttempt throttles invite retries: the exit rate-limits the
	// registration endpoint, so a failed attempt must not be repeated on every
	// health tick.
	lastRegisterAttempt time.Time
	// labelSynced records that the client name reached the exit during this
	// session. A rename made while the tunnel was down is sent again as soon as
	// the exit answers.
	labelSynced bool
	// registrationSynced records that this session has already told the exit
	// the device name and the app version. The server keeps those fields from
	// the last registration, so every connect refreshes them once: without it
	// the Clients page of X-Node kept showing the version the client had on the
	// day it redeemed its invite.
	registrationSynced bool

	// Peer supervisor state: when a configured peer was first seen down, the
	// cached public candidates and the last check.
	peerDownSince    map[string]time.Time
	lastPeerCheck    time.Time
	peerCandidates   []string
	peerCandidatesAt time.Time
	peerTopUpRunning bool

	// The public peer catalogue and the detected location are cached: the Peers
	// page asks for them on every visit and both need a network round-trip.
	catalogMu sync.Mutex
	catalog   []CatalogPeer
	catalogAt time.Time
	geoMu     sync.Mutex
	geo       *geoLocation
	geoAt     time.Time
	// exitGeo caches the place of an exit server by its host.
	exitGeoMu sync.Mutex
	exitGeo   map[string]geoLocation
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
		cfg:           cfg,
		logs:          NewLogBuffer(600),
		node:          yggnode.NewNode(),
		done:          make(chan struct{}),
		peerDownSince: make(map[string]time.Time),
	}
	a.node.SetLogger(a.logs)
	if cfg.LoggingDisabled {
		a.logs.SetEnabled(false)
	}
	// The built-in services were added by normalise(): write them back so the
	// catalogue is part of config.json instead of living only in memory.
	if cfg.pendingSave {
		if err := cfg.save(); err != nil {
			a.logs.Warnf("config.json: %v", err)
		}
	}
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
	// The probe rows belong to the core: the window never edits them, and a
	// configuration sent from the page would wipe the result of the last
	// discovery, leaving the Peers page empty after a restart.
	next.LastProbe = previous.LastProbe
	// The hidden catalogue entries are owned by the core as well: the window
	// has no field for them, so a settings change must not bring a deleted
	// built-in back. RestoreBuiltIns clears the list on its own.
	next.HiddenServices = previous.HiddenServices
	a.cfg = next
	running := a.running
	active, hasProfile := next.activeProfile()
	a.mu.Unlock()

	if err := next.save(); err != nil {
		return err
	}
	a.logs.SetEnabled(!next.LoggingDisabled)
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
	// The name the exit shows is part of the client record, so a change has to
	// be sent to the server again; otherwise the label would only update on the
	// next reconnect.
	if hasProfile &&
		(previous.ExitLabel != next.ExitLabel ||
			previous.ExitLabelEnabled != next.ExitLabelEnabled) {
		go a.syncExitLabel(active.ID, next.ExitLabelEnabled, next.ExitLabel)
	}
	return nil
}

// syncExitLabel sends the client name to the exit node. The registration
// endpoint only applies a label to a client that is not allowlisted yet, so a
// client that already has access renames itself through /v1/label. The source
// address of the request is the credential: the exit derives it from the
// Yggdrasil key and refuses to rename anybody else.
func (a *App) syncExitLabel(profileID string, enabled bool, name string) {
	label := deviceName()
	if enabled {
		if custom := strings.TrimSpace(name); custom != "" {
			label = custom
		}
	}
	raw := a.node.SetExitLabel(profileID, label)
	var payload struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
	}
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		a.logs.Warnf("exit label: %v", err)
		return
	}
	if !payload.OK {
		// A tunnel that is down or an exit that is older than /v1/label is not
		// an error the user has to see: the name travels with the next
		// registration as well.
		a.logs.Infof("exit label: %s", payload.Error)
		return
	}
	a.logs.Infof("exit label: %q", label)
}

// syncActiveExitLabel sends the name of the active profile. It runs after a
// connect and once per session when the exit comes online, so a rename made
// while the tunnel was down is applied as soon as the exit answers.
func (a *App) syncActiveExitLabel() {
	a.mu.Lock()
	profile, ok := a.cfg.activeProfile()
	enabled := a.cfg.ExitLabelEnabled
	name := a.cfg.ExitLabel
	a.mu.Unlock()
	if !ok {
		return
	}
	a.syncExitLabel(profile.ID, enabled, name)
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

	if a.node.IsRunning() {
		// A disconnect that failed in an older build could leave the node up.
		// Starting a second node is impossible, so the stale one is released
		// before a new session begins.
		a.logs.Warnf("connect: a previous node was still running, stopping it first")
		a.node.Stop()
	}

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
	a.labelSynced = false
	a.registrationSynced = false
	systemProxy := a.cfg.SystemProxy
	if a.sessionCancel != nil {
		a.sessionCancel()
	}
	sessionCtx, sessionCancel := context.WithCancel(context.Background())
	a.sessionCtx = sessionCtx
	a.sessionCancel = sessionCancel
	// A session owns its own stop channel. Disconnect closes the channel of the
	// session it stopped and clears the field, so a later Connect must create a
	// fresh one instead of closing an already closed channel. That second close
	// panicked the HTTP handler, which left the node and the proxy running while
	// the window already showed "disconnected".
	a.done = make(chan struct{})
	a.refreshDone = make(chan struct{})
	done := a.done
	refreshDone := a.refreshDone
	a.mu.Unlock()

	if systemProxy {
		if err := a.applySystemProxy(true); err != nil {
			a.logs.Warnf("system proxy: %v", err)
		}
	}

	go a.refreshLoop(sessionCtx, done, refreshDone)
	// A link imported while the tunnel was down carries an unused invite.
	// Redeem it in the background so Connect answers quickly, and ask the exit
	// about itself right away: the first status answer is what tells the proxy
	// whether the browser should be given IPv6 or IPv4 first, and what the
	// card shows about the exit.
	go func() {
		if sessionCtx.Err() != nil {
			return
		}
		a.ensureExitRegistration()
		a.mu.Lock()
		enabled := a.cfg.ExitEnabled && len(a.cfg.ExitProfiles) > 0
		timeout := len(a.cfg.ExitProfiles)*6000 + 4000
		a.mu.Unlock()
		if !enabled || sessionCtx.Err() != nil {
			return
		}
		a.node.CheckExitProfilesContext(sessionCtx, timeout)
		a.refreshState()
	}()
	go a.maintainPeers(true)
	a.refreshState()
	a.logs.Infof("connected: %s", a.node.GetAddress())
	return nil
}

// Disconnect stops the proxy and the node.
func (a *App) Disconnect() error {
	a.mu.Lock()
	running := a.running
	proxy := a.proxy
	wasSystemProxy := a.sysProxySet
	done := a.done
	refreshDone := a.refreshDone
	cancel := a.sessionCancel
	cfg := a.cfg
	a.running = false
	a.proxy = nil
	a.done = nil
	a.refreshDone = nil
	a.sessionCtx = nil
	a.sessionCancel = nil
	a.mu.Unlock()

	// A tunnel that is already down can still leave the system proxy on or a
	// node running: an older build could panic in the middle of Disconnect and
	// leave both behind. The quit path calls this, so the leftovers are cleaned
	// up even when the window believes the tunnel is already off.
	if !running && proxy == nil && !a.node.IsRunning() {
		recoverSystemProxy(cfg.Bind, cfg.HTTPPort)
		a.mu.Lock()
		a.sysProxySet = false
		a.mu.Unlock()
		return nil
	}

	// Cancel first: the health ticker may be inside CheckExitProfiles and the
	// peer supervisor may be probing candidates. Both have to stop before the
	// node is released, otherwise the window says "disconnected" while the
	// process is still talking to the Yggdrasil network.
	if cancel != nil {
		cancel()
	}
	if done != nil {
		close(done)
	}
	if wasSystemProxy {
		if err := setSystemProxy(false, "", 0); err != nil {
			a.logs.Warnf("system proxy: %v", err)
		}
	} else {
		// Only our own loopback address is cleared, so a corporate proxy the
		// user configured stays untouched.
		recoverSystemProxy(cfg.Bind, cfg.HTTPPort)
	}
	if proxy != nil {
		proxy.Stop()
	}
	a.node.Stop()
	// The node is down before the wait, so a status loop that is stuck in a
	// network call cannot keep the client on the Yggdrasil network. The wait is
	// bounded for the same reason: the disconnect itself must always finish.
	if refreshDone != nil {
		select {
		case <-refreshDone:
		case <-time.After(5 * time.Second):
			a.logs.Warnf("disconnect: the status loop did not stop in time")
		}
	}
	a.mu.Lock()
	a.sysProxySet = false
	a.mu.Unlock()
	if running {
		a.logs.Infof("disconnected")
	}
	return nil
}

// Shutdown stops everything; used when the process exits.
func (a *App) Shutdown() {
	_ = a.Disconnect()
}

// sessionContext returns the context of the running session. A stopped app has
// no session: callers that need the network return on a cancelled context.
func (a *App) sessionContext() context.Context {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.sessionCtx == nil {
		return context.Background()
	}
	return a.sessionCtx
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

// ensureSystemProxy re-applies the per-user proxy when the setting says it is
// on but the operating system no longer points at this core. A previous core
// that was killed, or another program, can clear the WinINET value while the
// tunnel keeps running: without this the browser goes direct and the user sees
// "some sites do not load" while the app still claims the tunnel is in use.
func (a *App) ensureSystemProxy() {
	a.mu.Lock()
	wanted := a.cfg.SystemProxy && a.running
	a.mu.Unlock()
	if !wanted {
		return
	}
	if enabled, _ := systemProxyState(); enabled {
		return
	}
	if err := a.applySystemProxy(true); err != nil {
		a.logs.Warnf("system proxy: %v", err)
		return
	}
	a.logs.Infof("system proxy restored")
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
		ExitInUse:   running && cfg.ExitEnabled && len(cfg.ExitProfiles) > 0 && exitStat == "online",
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
	} else if running && cfg.SystemProxy {
		// The setting is on but the operating system does not point at this
		// proxy any more. Reporting the setting here would tell the user the
		// traffic is tunnelled while the browser goes direct.
		state.SystemProxy = false
	}
	if profile, ok := cfg.activeProfile(); ok && cfg.ExitEnabled {
		if place, ok := a.exitPlace(profile.Peer); ok {
			state.ExitFlag = place.Flag
			state.ExitCountry = place.CountryName
			state.ExitCity = place.City
		}
	}
	// Rx is what the browser received through the proxy (the download), Tx is
	// what it sent (the upload). The proxy counts its own side, so its Down
	// counter is the download of the client.
	state.RxBytes = a.stats.Down.Load()
	state.TxBytes = a.stats.Up.Load()
	state.OpenConns = a.stats.Open.Load()
	state.TotalConns = a.stats.TotalOpen.Load()
	if running {
		state.Address = a.node.GetAddress()
		state.Subnet = a.node.GetSubnet()
		state.PublicKey = a.node.GetPublicKey()
		state.UptimeSecond = int64(time.Since(started).Seconds())
		var peers []struct {
			Up        bool    `json:"up"`
			LatencyMs float64 `json:"latencyMs"`
		}
		if err := json.Unmarshal([]byte(a.node.GetPeersJSON()), &peers); err == nil {
			state.PeersTotal = len(peers)
			best := 0.0
			for _, peer := range peers {
				if peer.Up {
					state.PeersUp++
					if peer.LatencyMs > 0 && (best == 0 || peer.LatencyMs < best) {
						best = peer.LatencyMs
					}
				}
			}
			state.LatencyMs = best
		}
	} else {
		state.Address, state.Subnet, state.PublicKey = a.Identity()
	}
	return state
}

// exitPlace returns the cached place of an exit server and starts the lookup
// when it is not known yet. The lookup runs once per host: the flag is a label,
// not a live measurement.
func (a *App) exitPlace(peerURI string) (geoLocation, bool) {
	host := peerHost(peerURI)
	if host == "" || strings.Contains(host, ":") {
		// A Yggdrasil address has no country of its own.
		return geoLocation{}, false
	}
	a.exitGeoMu.Lock()
	if a.exitGeo == nil {
		a.exitGeo = map[string]geoLocation{}
	}
	cached, ok := a.exitGeo[host]
	a.exitGeoMu.Unlock()
	if ok {
		return cached, cached.Flag != ""
	}
	go func() {
		place, found := lookupGeoAddress(host)
		if !found {
			return
		}
		a.exitGeoMu.Lock()
		a.exitGeo[host] = place
		a.exitGeoMu.Unlock()
	}()
	return geoLocation{}, false
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

// AddPeer stores a peer and applies it to the running node. A node that is in
// the replacement pool is moved into the tunnel instead of being duplicated.
func (a *App) AddPeer(uri string) error {
	uri = strings.TrimSpace(uri)
	if !isUsablePeer(uri) {
		return errors.New("this is not a Yggdrasil peer URI")
	}
	host := peerHost(uri)
	a.mu.Lock()
	for _, existing := range a.cfg.Peers {
		if existing == uri || peerHost(existing) == host {
			a.mu.Unlock()
			return errors.New("this peer is already in the tunnel")
		}
	}
	a.cfg.Peers = append(a.cfg.Peers, uri)
	a.cfg.Pool = removePeerURI(a.cfg.Pool, uri)
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

// RemovePoolPeer drops one spare node from the replacement pool.
func (a *App) RemovePoolPeer(uri string) error {
	a.mu.Lock()
	a.cfg.Pool = removePeerURI(a.cfg.Pool, uri)
	cfg := a.cfg
	a.mu.Unlock()
	return cfg.save()
}

func removePeerURI(list []string, uri string) []string {
	out := make([]string, 0, len(list))
	for _, existing := range list {
		if existing != uri {
			out = append(out, existing)
		}
	}
	return out
}

func peerHost(uri string) string {
	trimmed := strings.TrimSpace(uri)
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return trimmed
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "" {
		// A malformed entry must not collapse into the empty key and make every
		// other broken entry look like the same server.
		return trimmed
	}
	return host
}

// ExitProfiles returns the configured exit nodes.
func (a *App) ExitProfiles() ([]ExitProfile, string, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]ExitProfile(nil), a.cfg.ExitProfiles...), a.cfg.ExitActiveID, a.cfg.ExitEnabled
}

// ExitDismissed reports what the user removed from the active list while the
// exit node was off: its pinned peer and its resolver.
func (a *App) ExitDismissed() (peer bool, dns bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.cfg.ExitPeerHidden, a.cfg.ExitDNSHidden
}

// HideExitPeer takes the pinned peer of the exit node out of the active list.
// It only makes sense while the exit is off; switching it on brings the peer
// back.
func (a *App) HideExitPeer() error {
	a.mu.Lock()
	a.cfg.ExitPeerHidden = true
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	a.applyExitConfig()
	return nil
}

// HideExitDNS takes the resolver the exit publishes out of the tunnel list.
// The "DNS exit node" switch keeps its value, so switching the exit on adds the
// resolver back.
func (a *App) HideExitDNS() error {
	a.mu.Lock()
	a.cfg.ExitDNSHidden = true
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	a.applyExitConfig()
	return nil
}

// EditExit replaces one profile by its id, or adds it when the id is new. The
// invite and the token are kept when the window leaves them empty, so a form
// that was opened before the exit issued a token does not wipe it.
func (a *App) EditExit(next ExitProfile) (ExitProfile, error) {
	next.Name = strings.TrimSpace(next.Name)
	next.Address = strings.TrimSpace(next.Address)
	next.Peer = strings.TrimSpace(next.Peer)
	next.Invite = strings.TrimSpace(next.Invite)
	next.Token = strings.TrimSpace(next.Token)
	if !isYggdrasilAddress(next.Address) {
		return ExitProfile{}, errors.New("the address is not a Yggdrasil address")
	}
	if next.SocksPort < 1 || next.SocksPort > 65535 {
		return ExitProfile{}, errors.New("the SOCKS port is invalid")
	}
	if next.APIPort == 0 {
		next.APIPort = next.SocksPort
	}
	if next.APIPort < 1 || next.APIPort > 65535 {
		return ExitProfile{}, errors.New("the API port is invalid")
	}
	if next.Name == "" {
		next.Name = next.Address
	}
	if next.Peer != "" && !isUsablePeer(next.Peer) {
		return ExitProfile{}, errors.New("the peer address is not a Yggdrasil peering URI")
	}
	a.mu.Lock()
	replaced := false
	for index, existing := range a.cfg.ExitProfiles {
		if existing.ID != next.ID {
			continue
		}
		if next.Invite == "" {
			next.Invite = existing.Invite
		}
		if next.Token == "" {
			next.Token = existing.Token
		}
		next.Registered = existing.Registered
		if next.DNS == "" {
			next.DNS = existing.DNS
			next.DNSPort = existing.DNSPort
		}
		a.cfg.ExitProfiles[index] = next
		replaced = true
		break
	}
	if !replaced {
		if next.ID == "" {
			next.ID = fmt.Sprintf("%s:%d", next.Address, next.SocksPort)
		}
		a.cfg.ExitProfiles = append(a.cfg.ExitProfiles, next)
		if a.cfg.ExitActiveID == "" {
			a.cfg.ExitActiveID = next.ID
		}
	}
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return ExitProfile{}, err
	}
	if running {
		if err := a.node.SetDesktopExitConfig(cfg.exitJSON()); err != nil {
			return next, err
		}
	}
	return next, nil
}

// ReorderExits applies the order of the ids to the profile list.
func (a *App) ReorderExits(ids []string) error {
	a.mu.Lock()
	byID := make(map[string]ExitProfile, len(a.cfg.ExitProfiles))
	for _, profile := range a.cfg.ExitProfiles {
		byID[profile.ID] = profile
	}
	next := make([]ExitProfile, 0, len(a.cfg.ExitProfiles))
	seen := map[string]bool{}
	for _, id := range ids {
		profile, ok := byID[id]
		if !ok || seen[id] {
			continue
		}
		seen[id] = true
		next = append(next, profile)
	}
	for _, profile := range a.cfg.ExitProfiles {
		if !seen[profile.ID] {
			next = append(next, profile)
		}
	}
	a.cfg.ExitProfiles = next
	cfg := a.cfg
	a.mu.Unlock()
	return cfg.save()
}

// SaveProbeResults stores the rows of a latency test. The Peers page reads them
// back after a restart instead of showing an empty discovery card.
func (a *App) SaveProbeResults(rows []ProbeEntry) {
	a.mu.Lock()
	a.cfg.LastProbe = rows
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		a.logs.Warnf("save probe results: %v", err)
	}
}

// AddExitLink imports a yggnode://exit link and makes it active. The invite is
// stored even when the tunnel is down: registration is retried after connect,
// so importing a link before the first connection does not leave the client
// outside the allowlist.
func (a *App) AddExitLink(link string) (ExitProfile, error) {
	profile, invite, err := ParseExitLink(link)
	if err != nil {
		return ExitProfile{}, err
	}
	profile.Invite = invite
	profile.Registered = false
	a.mu.Lock()
	replaced := false
	for index, existing := range a.cfg.ExitProfiles {
		if existing.ID == profile.ID {
			profile.Token = existing.Token
			if invite == "" {
				profile.Invite = existing.Invite
				profile.Registered = existing.Registered
			}
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
	running := a.running
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return ExitProfile{}, err
	}

	// The bridge only knows the profiles from the last apply. Install the new
	// list before redeeming the invite, otherwise RegisterExit answers
	// "unknown_profile" even though the profile is already in config.json.
	a.applyExitConfig()

	if invite != "" {
		if running {
			a.registerExit(profile.ID, invite)
		} else {
			a.logs.Infof("exit %s: the invite is redeemed after the tunnel connects", profile.Name)
		}
	}

	return a.exitProfile(profile.ID)
}

// registerExit redeems one invite and stores what the answer carries. A failed
// attempt leaves Registered false, so ensureExitRegistration retries later.
func (a *App) registerExit(profileID, invite string) {
	a.mu.Lock()
	a.lastRegisterAttempt = time.Now()
	label := ""
	if a.cfg.ExitLabelEnabled {
		label = strings.TrimSpace(a.cfg.ExitLabel)
		if label == "" {
			label = deviceName()
		}
	}
	a.mu.Unlock()

	result := a.node.RegisterExit(profileID, invite, deviceName(), "Y-Node Desktop "+Version, label)
	var payload struct {
		OK      bool   `json:"ok"`
		Token   string `json:"token"`
		DNSAddr string `json:"dnsAddress"`
		DNSPort int    `json:"dnsPort"`
		Error   string `json:"error"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal([]byte(result), &payload); err != nil {
		a.logs.Warnf("exit registration: %v", err)
		return
	}
	if !payload.OK {
		a.logs.Warnf("exit registration: %s %s", payload.Error, payload.Message)
		return
	}

	a.mu.Lock()
	for index, existing := range a.cfg.ExitProfiles {
		if existing.ID != profileID {
			continue
		}
		a.cfg.ExitProfiles[index].Registered = true
		if payload.Token != "" {
			a.cfg.ExitProfiles[index].Token = payload.Token
		}
		if payload.DNSAddr != "" {
			a.cfg.ExitProfiles[index].DNS = payload.DNSAddr
			a.cfg.ExitProfiles[index].DNSPort = payload.DNSPort
		}
	}
	a.registrationSynced = true
	cfg := a.cfg
	name := profileID
	for _, profile := range cfg.ExitProfiles {
		if profile.ID == profileID {
			name = profile.Name
		}
	}
	a.mu.Unlock()
	_ = cfg.save()
	a.logs.Infof("registered with exit %s", name)
}

// ensureExitRegistration redeems the stored invite of the active profile and
// refreshes the device name and the app version of an already registered one.
// It is called after connect, before a check and from the health loop, so a
// link imported while the node was down becomes usable without the user
// pressing anything. A registered client registers with an empty invite: the
// server accepts that for an allowlisted address and updates the fields the
// Clients page shows, which is how the reported version stops being the one
// from the first invite.
func (a *App) ensureExitRegistration() {
	a.mu.Lock()
	running := a.running
	profile, ok := a.cfg.activeProfile()
	enabled := a.cfg.ExitEnabled
	synced := a.registrationSynced
	if !running || !ok || !enabled || synced {
		a.mu.Unlock()
		return
	}
	invite := strings.TrimSpace(profile.Invite)
	registered := profile.Registered || strings.TrimSpace(profile.Token) != ""
	// An unknown client needs the invite; a registered one only refreshes its
	// fields and must not depend on the invite still being unused.
	if invite == "" && !registered {
		a.mu.Unlock()
		return
	}
	if time.Since(a.lastRegisterAttempt) < 90*time.Second {
		a.mu.Unlock()
		return
	}
	a.mu.Unlock()
	a.registerExit(profile.ID, invite)
}

// exitProfile returns one profile by id after the registration may have changed
// it.
func (a *App) exitProfile(id string) (ExitProfile, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, profile := range a.cfg.ExitProfiles {
		if profile.ID == id {
			return profile, nil
		}
	}
	return ExitProfile{}, errors.New("unknown exit profile")
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
		// The resolver of the removed node is not a local resolver: leaving it
		// in exitDns made every ordinary lookup go to an address only the
		// Yggdrasil network can reach, which broke the proxy for normal sites.
		a.cfg.ExitDNS = nil
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
	a.ensureExitRegistration()
	return nil
}

// SetExitEnabled turns public traffic through the exit on or off.
func (a *App) SetExitEnabled(enable bool) error {
	a.mu.Lock()
	a.cfg.ExitEnabled = enable && len(a.cfg.ExitProfiles) > 0
	if a.cfg.ExitEnabled {
		// The peer and the resolver removed while the exit was off come back
		// with the switch: the cross on the row is not a permanent delete.
		a.cfg.ExitPeerHidden = false
		a.cfg.ExitDNSHidden = false
	}
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

// CheckExit asks every profile's status API whether this client is allowed and
// returns a short report the window shows in a dialog. The report always has an
// "ok" field: the window used to look for it in the raw status JSON, which does
// not carry one, so every check ended with "The exit node did not answer".
func (a *App) CheckExit() string {
	a.mu.Lock()
	running := a.running
	profiles := append([]ExitProfile(nil), a.cfg.ExitProfiles...)
	activeID := a.cfg.ExitActiveID
	a.mu.Unlock()
	if !running {
		return `{"ok":false,"message":"The tunnel is not running. Connect first."}`
	}
	if len(profiles) == 0 {
		return `{"ok":false,"message":"No exit node is configured."}`
	}
	// A check is the natural moment to redeem a pending invite: the user is
	// asking why the node does not answer, and the answer may be "the invite
	// was never registered".
	a.ensureExitRegistration()
	timeout := len(profiles)*6000 + 4000
	raw := a.node.CheckExitProfiles(timeout)
	var status struct {
		State    string `json:"state"`
		ActiveID string `json:"activeId"`
		Profiles []struct {
			ID         string  `json:"id"`
			Name       string  `json:"name"`
			State      string  `json:"state"`
			LatencyMs  float64 `json:"latencyMs"`
			Error      string  `json:"error"`
			DNSAddress string  `json:"dnsAddress"`
			DNSPort    int     `json:"dnsPort"`
			Suspended  bool    `json:"suspended"`
		} `json:"profiles"`
	}
	if err := json.Unmarshal([]byte(raw), &status); err != nil {
		payload, _ := json.Marshal(map[string]any{
			"ok": false, "message": "The exit status could not be read: " + err.Error(),
		})
		return string(payload)
	}
	active := status.ActiveID
	if active == "" {
		active = activeID
	}
	name := ""
	for _, profile := range status.Profiles {
		if active == "" || profile.ID == active {
			name = profile.Name
			if profile.State == "online" {
				message := name + " answered"
				if profile.LatencyMs > 0 {
					message += fmt.Sprintf(" in %.0f ms", profile.LatencyMs)
				}
				if profile.DNSAddress != "" {
					message += fmt.Sprintf(" · DNS %s", net.JoinHostPort(profile.DNSAddress, fmt.Sprint(profile.DNSPort)))
				}
				payload, _ := json.Marshal(map[string]any{
					"ok":         true,
					"state":      profile.State,
					"message":    message,
					"dnsAddress": profile.DNSAddress,
					"dnsPort":    profile.DNSPort,
				})
				return string(payload)
			}
			message := name + " did not answer"
			switch profile.State {
			case "denied":
				message = name + " is not in the allowlist"
				if profile.Suspended {
					message = name + " suspended this client"
				}
			case "unreachable":
				if profile.Error != "" {
					message = name + " is unreachable: " + profile.Error
				}
			}
			payload, _ := json.Marshal(map[string]any{
				"ok":      false,
				"state":   profile.State,
				"message": message,
			})
			return string(payload)
		}
	}
	payload, _ := json.Marshal(map[string]any{
		"ok":      false,
		"state":   status.State,
		"message": "The active exit node is not in the status answer.",
	})
	return string(payload)
}

// CheckDNS probes a list of resolvers and returns the JSON array the window
// shows. In-network servers are checked through the node (they resolve real
// .ygg names), ordinary ones directly (they resolve example.com).
func (a *App) CheckDNS(servers []string, direct bool) string {
	if len(servers) == 0 {
		return `[]`
	}
	if !direct {
		payload, _ := json.Marshal(servers)
		return a.node.CheckDNS(string(payload), 8000)
	}
	out := make([]json.RawMessage, 0, len(servers))
	for _, server := range servers {
		out = append(out, json.RawMessage(a.node.CheckSystemDNS(server, 8000)))
	}
	raw, err := json.Marshal(out)
	if err != nil {
		return `[]`
	}
	return string(raw)
}

// SetPeerSettings stores how many automatic peers the supervisor keeps and
// whether a dead one may be replaced. The change applies at once.
func (a *App) SetPeerSettings(count int, autoReplace bool) error {
	if count < 1 {
		count = 1
	}
	if count > 20 {
		count = 20
	}
	a.mu.Lock()
	a.cfg.PeerCount = count
	a.cfg.PeerAutoReplace = autoReplace
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return err
	}
	go a.maintainPeers(true)
	return nil
}

// maintainPeers keeps the configured peer list at the requested size, the way
// the Android supervisor does: a peer that stays down for the dead timeout is
// dropped and replaced with a probed candidate, and a short list is topped up.
func (a *App) maintainPeers(force bool) {
	ctx := a.sessionContext()
	if ctx.Err() != nil {
		return
	}
	a.mu.Lock()
	if !a.running {
		a.mu.Unlock()
		return
	}
	interval, _ := time.ParseDuration(a.cfg.PeerCheckInterval)
	if interval < 10*time.Second {
		interval = 30 * time.Second
	}
	if !force && time.Since(a.lastPeerCheck) < interval {
		a.mu.Unlock()
		return
	}
	a.lastPeerCheck = time.Now()
	deadTimeout, _ := time.ParseDuration(a.cfg.PeerDeadTimeout)
	if deadTimeout < 30*time.Second {
		deadTimeout = 90 * time.Second
	}
	want := a.cfg.PeerCount
	autoReplace := a.cfg.PeerAutoReplace
	configured := append([]string(nil), a.cfg.Peers...)
	a.mu.Unlock()

	live := map[string]bool{}
	var rows []struct {
		URI       string  `json:"uri"`
		Up        bool    `json:"up"`
		LatencyMs float64 `json:"latencyMs"`
	}
	if err := json.Unmarshal([]byte(a.node.GetPeersJSON()), &rows); err == nil {
		// The node reports the URI it was given, but a normalised link (the
		// pinned exit peer loses its query, a transport may be rewritten) must
		// still count as the same server: comparing hosts keeps a live peer
		// from being replaced. Two transports of one host collapse into one
		// entry, and a single live transport is enough.
		//
		// A link is live only when the overlay measures it: the core keeps the
		// TCP socket open after ironwood has already dropped the peer, so such
		// a link reports "up" while nothing is routed through it and the
		// latency stays zero.
		for _, row := range rows {
			host := peerHost(row.URI)
			live[host] = live[host] || (row.Up && row.LatencyMs > 0)
		}
	}

	now := time.Now()
	a.mu.Lock()
	changed := false
	kept := make([]string, 0, len(configured))
	for _, uri := range configured {
		if live[peerHost(uri)] {
			delete(a.peerDownSince, uri)
			kept = append(kept, uri)
			continue
		}
		since, ok := a.peerDownSince[uri]
		if !ok {
			a.peerDownSince[uri] = now
		}
		if autoReplace && ok && now.Sub(since) > deadTimeout {
			a.logs.Warnf("peer %s is down for %s, replacing it", uri, deadTimeout)
			delete(a.peerDownSince, uri)
			changed = true
			continue
		}
		kept = append(kept, uri)
	}
	if changed {
		// The replacement pool is the first source: those nodes answered a probe
		// and are already known, so no download is needed to keep the list full.
		for len(kept) < want && len(a.cfg.Pool) > 0 {
			kept = append(kept, a.cfg.Pool[0])
			a.cfg.Pool = a.cfg.Pool[1:]
		}
		a.cfg.Peers = kept
	}
	cfg := a.cfg
	a.mu.Unlock()
	if changed {
		if err := cfg.save(); err != nil {
			a.logs.Warnf("save peers: %v", err)
		}
		if payload, err := json.Marshal(cfg.peerList()); err == nil {
			if err := a.node.SetPeers(string(payload)); err != nil {
				a.logs.Warnf("apply peers: %v", err)
			}
		}
	}
	// "want" is the size of the configured list, not the number of links that
	// are up: a peer that is still connecting must not be duplicated by a
	// candidate. Only a list shorter than the target is topped up.
	if len(kept) < want && ctx.Err() == nil {
		go a.topUpPeers(ctx, want-len(kept))
	}
}

// topUpPeers appends the fastest public candidates until the configured list
// has the requested size. Candidates are cached for ten minutes, so a flapping
// peer does not download the catalogue on every check. The context is the
// tunnel session: a probe that is still running when the user disconnects stops
// at once and its result is dropped.
func (a *App) topUpPeers(ctx context.Context, need int) {
	if need <= 0 || ctx.Err() != nil {
		return
	}
	a.mu.Lock()
	if a.peerTopUpRunning {
		a.mu.Unlock()
		return
	}
	a.peerTopUpRunning = true
	// The replacement pool comes first: those nodes were probed already.
	fromPool := need
	if fromPool > len(a.cfg.Pool) {
		fromPool = len(a.cfg.Pool)
	}
	if fromPool > 0 {
		a.cfg.Peers = append(a.cfg.Peers, a.cfg.Pool[:fromPool]...)
		a.cfg.Pool = a.cfg.Pool[fromPool:]
	}
	cfg := a.cfg
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.peerTopUpRunning = false
		a.mu.Unlock()
	}()
	if fromPool > 0 {
		if err := cfg.save(); err != nil {
			a.logs.Warnf("save peers: %v", err)
		} else if payload, err := json.Marshal(cfg.peerList()); err == nil {
			if err := a.node.SetPeers(string(payload)); err != nil {
				a.logs.Warnf("apply peers: %v", err)
			}
		}
		need -= fromPool
	}
	if need <= 0 {
		return
	}
	a.mu.Lock()
	candidates := append([]string(nil), a.peerCandidates...)
	fresh := time.Since(a.peerCandidatesAt) < 10*time.Minute
	a.mu.Unlock()
	if len(candidates) == 0 || !fresh {
		if ctx.Err() != nil {
			return
		}
		list := a.DiscoveryTargets(120)
		if ctx.Err() != nil {
			return
		}
		if len(list) == 0 {
			a.logs.Warnf("public peers: the catalogue is not available")
			list = append([]string(nil), seedPeers...)
		}
		a.mu.Lock()
		a.peerCandidates = list
		a.peerCandidatesAt = time.Now()
		a.mu.Unlock()
		candidates = list
	}

	if ctx.Err() != nil {
		return
	}

	a.mu.Lock()
	known := make(map[string]bool, len(a.cfg.Peers))
	for _, uri := range a.cfg.Peers {
		known[peerHost(uri)] = true
	}
	a.mu.Unlock()
	probe := make([]string, 0, 24)
	for _, uri := range candidates {
		if known[peerHost(uri)] {
			continue
		}
		probe = append(probe, uri)
		if len(probe) >= 24 {
			break
		}
	}
	if len(probe) == 0 {
		return
	}
	payload, _ := json.Marshal(probe)
	raw := yggnode.ProbePeersContext(ctx, string(payload), 12000, a.logs)
	if ctx.Err() != nil {
		return
	}
	var results []struct {
		URI       string  `json:"uri"`
		Up        bool    `json:"up"`
		LatencyMs float64 `json:"latencyMs"`
	}
	if err := json.Unmarshal([]byte(raw), &results); err != nil {
		return
	}
	up := make([]struct {
		uri     string
		latency float64
	}, 0, len(results))
	for _, result := range results {
		if result.Up {
			up = append(up, struct {
				uri     string
				latency float64
			}{result.URI, result.LatencyMs})
		}
	}
	sort.Slice(up, func(i, j int) bool { return up[i].latency < up[j].latency })
	if len(up) > need {
		up = up[:need]
	}
	if len(up) == 0 {
		return
	}
	a.mu.Lock()
	for _, item := range up {
		a.cfg.Peers = append(a.cfg.Peers, item.uri)
	}
	cfg = a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		a.logs.Warnf("save peers: %v", err)
		return
	}
	if payload, err := json.Marshal(cfg.peerList()); err == nil {
		if err := a.node.SetPeers(string(payload)); err != nil {
			a.logs.Warnf("apply peers: %v", err)
		}
	}
	for _, item := range up {
		a.logs.Infof("peer added: %s (%.0f ms)", item.uri, item.latency)
	}
}

// ExitStatus returns the last exit state as JSON.
func (a *App) ExitStatus() string {
	return a.node.GetExitStatusJSON()
}

// refreshLoop keeps the snapshot fresh and polls the exit health. The context
// is cancelled by Disconnect: a check that is already running returns instead
// of keeping the node busy after the tunnel is down.
func (a *App) refreshLoop(ctx context.Context, done <-chan struct{}, finished chan<- struct{}) {
	defer close(finished)
	ticker := time.NewTicker(2 * time.Second)
	// The exit is asked every 15 seconds, the same cadence the Android client
	// uses: a setting changed on the server (IPv6 off, for example) has to show
	// up on the card without the user pressing "Check now".
	health := time.NewTicker(15 * time.Second)
	peers := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	defer health.Stop()
	defer peers.Stop()
	for {
		select {
		case <-done:
			return
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.refreshState()
		case <-peers.C:
			a.maintainPeers(false)
		case <-health.C:
			a.mu.Lock()
			enabled := a.cfg.ExitEnabled && len(a.cfg.ExitProfiles) > 0
			a.mu.Unlock()
			if enabled && ctx.Err() == nil {
				a.ensureExitRegistration()
				a.node.CheckExitProfilesContext(ctx, 9000)
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
	a.ensureSystemProxy()
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
	// The resolver the exit publishes belongs to the "DNS exit node" switch: it
	// is added to the in-network list by exitJSON and never written into the
	// public Exit DNS list. The config of the running node still has to follow a
	// resolver that appeared or changed.
	resolverChanged := false
	labelPending := status.State == "online" && !a.labelSynced
	if labelPending {
		a.labelSynced = true
	}
	for _, item := range status.Profiles {
		for index, profile := range a.cfg.ExitProfiles {
			if profile.ID != item.ID {
				continue
			}
			if item.Token != "" && item.Token != profile.Token {
				a.cfg.ExitProfiles[index].Token = item.Token
				a.cfg.ExitProfiles[index].Registered = true
				// The invite stays in the profile: the Exit page shows it in the
				// edit form, and the same one-time secret is what the Android
				// client keeps for a repeated registration.
				changed = true
			}
			if item.DNSKnown && item.DNSAddress != "" && profile.DNS != item.DNSAddress {
				a.cfg.ExitProfiles[index].DNS = item.DNSAddress
				a.cfg.ExitProfiles[index].DNSPort = item.DNSPort
				changed = true
				resolverChanged = true
			}
		}
	}
	a.exitDNS = dns
	if changed {
		cfg := a.cfg
		_ = cfg.save()
	}
	a.mu.Unlock()
	if labelPending {
		// The tunnel is up and the exit answers: send the client name that was
		// changed while it was down. The call goes through the tunnel, so it
		// must not hold the status loop.
		go a.syncActiveExitLabel()
	}
	if resolverChanged {
		a.logs.Infof("exit resolver: %s", dns)
		a.applyExitConfig()
	}
}
