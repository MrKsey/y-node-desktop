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
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/MrKsey/y-node-desktop/core/internal/yggnode"
)

// The public peer list is the same repository the Android client uses: markdown
// files grouped by continent and country, with the connection strings in
// backticks. The desktop app only needs the URIs, so the archive is walked with
// one regular expression instead of a markdown parser.
const publicPeersURL = "https://codeload.github.com/yggdrasil-network/public-peers/zip/refs/heads/master"

var peerPattern = regexp.MustCompile("`([a-z]+://[^`\\s]+)`")

var seedPeers = []string{
	"tls://box.paulll.cc:13338",
	"tcp://yggno.de:18226",
	"quic://novosibirsk.mie.foundation:9952",
}

var schemeRank = map[string]int{"tls": 0, "tcp": 1, "wss": 2, "ws": 3, "quic": 4}

// PublicPeers downloads the list and returns one URI per host, best transport
// first.
func (a *App) PublicPeers() ([]string, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Get(publicPeersURL)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("the peer list answered %s", response.Status)
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, 16<<20))
	if err != nil {
		return nil, err
	}
	archive, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return nil, err
	}

	best := make(map[string]string)
	for _, file := range archive.File {
		if !strings.HasSuffix(file.Name, ".md") {
			continue
		}
		reader, err := file.Open()
		if err != nil {
			continue
		}
		content, err := io.ReadAll(io.LimitReader(reader, 1<<20))
		_ = reader.Close()
		if err != nil {
			continue
		}
		for _, match := range peerPattern.FindAllStringSubmatch(string(content), -1) {
			uri := strings.TrimSpace(match[1])
			if !isUsablePeer(uri) {
				continue
			}
			parsed, err := url.Parse(uri)
			if err != nil {
				continue
			}
			host := strings.ToLower(parsed.Hostname())
			if previous, ok := best[host]; ok {
				if schemeRank[parsed.Scheme] >= schemeRank[mustScheme(previous)] {
					continue
				}
			}
			best[host] = uri
		}
	}
	if len(best) == 0 {
		return nil, errors.New("the peer list has no usable peers")
	}
	out := make([]string, 0, len(best))
	for _, uri := range best {
		out = append(out, uri)
	}
	sort.Slice(out, func(i, j int) bool {
		return schemeRank[mustScheme(out[i])] < schemeRank[mustScheme(out[j])]
	})
	if len(out) > 80 {
		out = out[:80]
	}
	return out, nil
}

func mustScheme(uri string) string {
	parsed, err := url.Parse(uri)
	if err != nil {
		return ""
	}
	return parsed.Scheme
}

// AutoPeers probes the public list and keeps the fastest nodes. A list that
// cannot be downloaded falls back to the built-in seeds, so the first run still
// has something to connect to.
func (a *App) AutoPeers(count int) ([]string, error) {
	if count < 1 {
		count = 3
	}
	candidates, err := a.PublicPeers()
	if err != nil {
		a.logs.Warnf("public peers: %v", err)
		candidates = append([]string(nil), seedPeers...)
	}
	if len(candidates) > 32 {
		candidates = candidates[:32]
	}
	payload, _ := json.Marshal(candidates)
	raw := yggnode.ProbePeers(string(payload), 15000, a.logs)
	var results []struct {
		URI       string  `json:"uri"`
		Up        bool    `json:"up"`
		LatencyMs float64 `json:"latencyMs"`
		Error     string  `json:"error"`
	}
	if err := json.Unmarshal([]byte(raw), &results); err != nil {
		return nil, err
	}
	var up []struct {
		uri     string
		latency float64
	}
	for _, result := range results {
		if result.Up {
			up = append(up, struct {
				uri     string
				latency float64
			}{result.URI, result.LatencyMs})
		}
	}
	sort.Slice(up, func(i, j int) bool { return up[i].latency < up[j].latency })
	chosen := make([]string, 0, count)
	for _, item := range up {
		chosen = append(chosen, item.uri)
		if len(chosen) >= count {
			break
		}
	}
	if len(chosen) == 0 {
		chosen = append(chosen, seedPeers[:count]...)
		a.logs.Warnf("no public peer answered, the built-in seeds are used")
	}

	a.mu.Lock()
	a.cfg.Peers = chosen
	cfg := a.cfg
	running := a.running
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return nil, err
	}
	if running {
		list, _ := json.Marshal(cfg.peerList())
		if err := a.node.SetPeers(string(list)); err != nil {
			a.logs.Warnf("apply peers: %v", err)
		}
	}
	a.logs.Infof("auto peers: %s", strings.Join(chosen, ", "))
	return chosen, nil
}

// ProbePeers checks the given peers and returns the live rows.
func (a *App) ProbePeers(uris []string) string {
	payload, _ := json.Marshal(uris)
	return yggnode.ProbePeers(string(payload), 12000, a.logs)
}
