package desktop

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// API is the loopback interface between the window and the core process. It is
// bound to 127.0.0.1 only: the desktop app has no remote control.
type API struct {
	app *App
}

func NewAPI(app *App) *API { return &API{app: app} }

func (a *API) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, map[string]any{"ok": true, "version": Version})
	})
	// POST /v1/quit is the uninstall path. Removing the installation while the
	// core runs leaves the system proxy pointing at a closed port and keeps the
	// TUN adapter busy, so the uninstaller asks the core to stop the tunnel and
	// restore the proxy first, and only then deletes the files. The window is a
	// separate process and is stopped by the same script afterwards.
	mux.HandleFunc("POST /v1/quit", func(rw http.ResponseWriter, _ *http.Request) {
		a.app.Shutdown()
		writeJSON(rw, http.StatusOK, map[string]any{"ok": true})
		go func() {
			// The answer has to reach the uninstaller before the process goes.
			time.Sleep(200 * time.Millisecond)
			os.Exit(0)
		}()
	})
	mux.HandleFunc("GET /v1/state", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("GET /v1/identity", func(rw http.ResponseWriter, _ *http.Request) {
		address, subnet, key := a.app.Identity()
		writeJSON(rw, http.StatusOK, map[string]string{
			"address": address, "subnet": subnet, "publicKey": key,
		})
	})
	mux.HandleFunc("POST /v1/connect", func(rw http.ResponseWriter, _ *http.Request) {
		if err := a.app.Connect(); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("POST /v1/disconnect", func(rw http.ResponseWriter, _ *http.Request) {
		if err := a.app.Disconnect(); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("POST /v1/system-proxy", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SetSystemProxy(body.Enabled); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})

	mux.HandleFunc("GET /v1/config", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, a.app.Config())
	})
	mux.HandleFunc("PUT /v1/config", func(rw http.ResponseWriter, r *http.Request) {
		var next Config
		if err := decode(r, &next); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SaveConfig(next); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.Config())
	})

	mux.HandleFunc("GET /v1/peers", func(rw http.ResponseWriter, _ *http.Request) {
		cfg := a.app.Config()
		writeJSON(rw, http.StatusOK, map[string]any{
			"live":       a.app.Peers(),
			"configured": cfg.Peers,
			"pool":       cfg.Pool,
			"probe":      cfg.LastProbe,
		})
	})
	mux.HandleFunc("GET /v1/peers/catalog", func(rw http.ResponseWriter, _ *http.Request) {
		peers, updated, err := a.app.PublicPeersCatalog()
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{
			"peers":     peers,
			"countries": a.app.CatalogCountries(),
			"detected":  a.app.Geo(),
			"country":   a.app.Config().CountrySlug,
			"updated":   updated,
		})
	})
	mux.HandleFunc("POST /v1/country", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Slug string `json:"slug"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SetCountry(body.Slug); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.Config())
	})
	mux.HandleFunc("POST /v1/ip", func(rw http.ResponseWriter, r *http.Request) {
		via := r.URL.Query().Get("via")
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.PublicIP(via)))
	})
	mux.HandleFunc("POST /v1/exit/udp-test", func(rw http.ResponseWriter, _ *http.Request) {
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.TestExitUDP()))
	})
	mux.HandleFunc("POST /v1/exit/ipv6-test", func(rw http.ResponseWriter, _ *http.Request) {
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.TestExitIPv6()))
	})
	mux.HandleFunc("POST /v1/peers", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			URI string `json:"uri"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.AddPeer(body.URI); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.Config().Peers)
	})
	mux.HandleFunc("DELETE /v1/peers", func(rw http.ResponseWriter, r *http.Request) {
		uri := r.URL.Query().Get("uri")
		var err error
		if r.URL.Query().Get("pool") == "1" {
			err = a.app.RemovePoolPeer(uri)
		} else {
			err = a.app.RemovePeer(uri)
		}
		if err != nil {
			writeError(rw, err)
			return
		}
		cfg := a.app.Config()
		writeJSON(rw, http.StatusOK, map[string]any{
			"configured": cfg.Peers,
			"pool":       cfg.Pool,
		})
	})
	mux.HandleFunc("PUT /v1/peers", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			URIs []string `json:"uris"`
			Pool []string `json:"pool"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SetPeers(body.URIs, body.Pool); err != nil {
			writeError(rw, err)
			return
		}
		cfg := a.app.Config()
		writeJSON(rw, http.StatusOK, map[string]any{
			"configured": cfg.Peers,
			"pool":       cfg.Pool,
		})
	})
	mux.HandleFunc("POST /v1/peers/catalog", func(rw http.ResponseWriter, _ *http.Request) {
		report, err := a.app.CatalogPeers()
		if err != nil {
			writeError(rw, err)
			return
		}
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(report))
	})
	mux.HandleFunc("POST /v1/peers/auto", func(rw http.ResponseWriter, _ *http.Request) {
		count := a.app.Config().PeerCount
		if count < 1 {
			count = 3
		}
		peers, err := a.app.AutoPeers(count)
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{"peers": peers})
	})
	mux.HandleFunc("POST /v1/peers/settings", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Count       int  `json:"count"`
			AutoReplace bool `json:"autoReplace"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SetPeerSettings(body.Count, body.AutoReplace); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.Config())
	})
	mux.HandleFunc("POST /v1/peers/find", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Limit int `json:"limit"`
		}
		// The body is optional: without it the core picks the size itself.
		_ = decode(r, &body)
		targets := a.app.DiscoveryTargets(body.Limit)
		if len(targets) == 0 {
			writeError(rw, errors.New("the public peer list is not available"))
			return
		}
		rw.Header().Set("Content-Type", "application/json")
		// A round of a hundred servers needs longer than the single-shot probe:
		// the connections are opened together and the slowest handshake decides
		// the end of the round.
		_, _ = rw.Write([]byte(a.app.probeAndStore(targets, 20000, true)))
	})
	mux.HandleFunc("POST /v1/peers/probe", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			URIs []string `json:"uris"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.probeAndStore(body.URIs, 12000, false)))
	})

	mux.HandleFunc("GET /v1/exit", func(rw http.ResponseWriter, _ *http.Request) {
		profiles, active, enabled := a.app.ExitProfiles()
		writeJSON(rw, http.StatusOK, map[string]any{
			"profiles": profiles, "activeId": active, "enabled": enabled,
		})
	})
	mux.HandleFunc("POST /v1/exit/link", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Link string `json:"link"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		profile, err := a.app.AddExitLink(body.Link)
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, profile)
	})
	mux.HandleFunc("POST /v1/exit/active", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			ID string `json:"id"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SetExitActive(body.ID); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("POST /v1/exit/enabled", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Enabled bool `json:"enabled"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.SetExitEnabled(body.Enabled); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("DELETE /v1/exit", func(rw http.ResponseWriter, r *http.Request) {
		if err := a.app.RemoveExit(r.URL.Query().Get("id")); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("POST /v1/exit/profile", func(rw http.ResponseWriter, r *http.Request) {
		var profile ExitProfile
		if err := decode(r, &profile); err != nil {
			writeError(rw, err)
			return
		}
		saved, err := a.app.EditExit(profile)
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{"profile": saved})
	})
	mux.HandleFunc("PUT /v1/exit/order", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			IDs []string `json:"ids"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.ReorderExits(body.IDs); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.State())
	})
	mux.HandleFunc("POST /v1/exit/check", func(rw http.ResponseWriter, _ *http.Request) {
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.CheckExit()))
	})
	mux.HandleFunc("GET /v1/exit/status", func(rw http.ResponseWriter, _ *http.Request) {
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.ExitStatus()))
	})
	mux.HandleFunc("GET /v1/dns/presets", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, map[string]any{"servers": dnsPresets()})
	})
	mux.HandleFunc("POST /v1/dns/check", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			Servers []string `json:"servers"`
			Direct  bool     `json:"direct"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.CheckDNS(body.Servers, body.Direct)))
	})
	mux.HandleFunc("GET /v1/logs", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, a.app.Logs())
	})
	mux.HandleFunc("GET /v1/services", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, map[string]any{
			"services": a.app.Services(),
			"hidden":   a.app.HiddenServices(),
		})
	})
	mux.HandleFunc("POST /v1/services", func(rw http.ResponseWriter, r *http.Request) {
		var entry ServiceEntry
		if err := decode(r, &entry); err != nil {
			writeError(rw, err)
			return
		}
		saved, err := a.app.SaveService(entry)
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{
			"service":  saved,
			"services": a.app.Services(),
			"hidden":   a.app.HiddenServices(),
		})
	})
	mux.HandleFunc("POST /v1/services/restore", func(rw http.ResponseWriter, _ *http.Request) {
		if err := a.app.RestoreBuiltIns(); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{
			"services": a.app.Services(),
			"hidden":   a.app.HiddenServices(),
		})
	})
	mux.HandleFunc("DELETE /v1/services", func(rw http.ResponseWriter, r *http.Request) {
		var err error
		if ids := r.URL.Query()["id"]; len(ids) > 0 {
			_, err = a.app.RemoveServices(ids)
		} else if id := r.URL.Query().Get("id"); id != "" {
			err = a.app.RemoveService(id)
		} else {
			// Older windows send the URL; keep accepting it.
			err = a.app.RemoveServiceByURL(r.URL.Query().Get("url"))
		}
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{
			"services": a.app.Services(),
			"hidden":   a.app.HiddenServices(),
		})
	})
	mux.HandleFunc("PUT /v1/services/order", func(rw http.ResponseWriter, r *http.Request) {
		var body struct {
			IDs []string `json:"ids"`
		}
		if err := decode(r, &body); err != nil {
			writeError(rw, err)
			return
		}
		if err := a.app.ReorderServices(body.IDs); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{
			"services": a.app.Services(),
			"hidden":   a.app.HiddenServices(),
		})
	})
	mux.HandleFunc("POST /v1/directory", func(rw http.ResponseWriter, _ *http.Request) {
		entries, err := a.app.ReadDirectory()
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{"resources": entries})
	})

	return withCommonHeaders(mux)
}

func withCommonHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		rw.Header().Set("Access-Control-Allow-Origin", "*")
		rw.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		rw.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		rw.Header().Set("Cache-Control", "no-store")
		if r.Method == http.MethodOptions {
			rw.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(rw, r)
	})
}

func decode(r *http.Request, out any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	return decoder.Decode(out)
}

func writeJSON(rw http.ResponseWriter, status int, value any) {
	rw.Header().Set("Content-Type", "application/json")
	rw.WriteHeader(status)
	_ = json.NewEncoder(rw).Encode(value)
}

func writeError(rw http.ResponseWriter, err error) {
	writeJSON(rw, http.StatusBadRequest, map[string]any{"ok": false, "error": strings.TrimSpace(err.Error())})
}
