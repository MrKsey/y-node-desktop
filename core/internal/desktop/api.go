package desktop

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
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
		writeJSON(rw, http.StatusOK, map[string]any{
			"live":       a.app.Peers(),
			"configured": a.app.Config().Peers,
		})
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
		if err := a.app.RemovePeer(uri); err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, a.app.Config().Peers)
	})
	mux.HandleFunc("POST /v1/peers/auto", func(rw http.ResponseWriter, _ *http.Request) {
		peers, err := a.app.AutoPeers(3)
		if err != nil {
			writeError(rw, err)
			return
		}
		writeJSON(rw, http.StatusOK, map[string]any{"peers": peers})
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
		_, _ = rw.Write([]byte(a.app.ProbePeers(body.URIs)))
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
	mux.HandleFunc("POST /v1/exit/check", func(rw http.ResponseWriter, _ *http.Request) {
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.CheckExit()))
	})
	mux.HandleFunc("GET /v1/exit/status", func(rw http.ResponseWriter, _ *http.Request) {
		rw.Header().Set("Content-Type", "application/json")
		_, _ = rw.Write([]byte(a.app.ExitStatus()))
	})
	mux.HandleFunc("GET /v1/logs", func(rw http.ResponseWriter, _ *http.Request) {
		writeJSON(rw, http.StatusOK, a.app.Logs())
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
