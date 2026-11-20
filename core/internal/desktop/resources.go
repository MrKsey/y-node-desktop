package desktop

import (
	"encoding/json"
	"errors"
	"net/url"
	"regexp"
	"strings"
)

// directoryURL is the web directory the cloud button on the Services page
// reads. It lives inside Yggdrasil and is only reachable through the node.
const directoryURL = "http://[21e:a51c:885b:7db0:166e:927:98cd:d186]/"

// builtInServices is the catalogue every installation starts with, the same
// eight entries the Android address book ships.
func builtInServices() []ServiceEntry {
	return []ServiceEntry{
		{
			ID:          "builtin:directory",
			Title:       "Yggdrasil Web directory",
			URL:         "http://[21e:a51c:885b:7db0:166e:927:98cd:d186]/",
			Description: "A catalogue of sites published inside Yggdrasil",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:howto",
			Title:       "HowTo Ygg",
			URL:         "http://[222:a8e4:50cd:55c:788e:b0a5:4e2f:a92c]/",
			Description: "Guides, articles and cheatsheets (Yggdrasil wiki)",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:forum",
			Title:       "Forum in Yggdrasil",
			URL:         "http://[21a:34aa:c782:3ad2:1bf8:73f8:141:66e8]/",
			Description: "A forum in Yggdrasil, about Yggdrasil",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:librespeed",
			Title:       "LibreSpeed instance",
			URL:         "http://[300:ffb4:8643:34d8::f1fa:1]/",
			Description: "Measure the throughput of your Yggdrasil link",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:peers",
			Title:       "Public peers",
			URL:         "http://[200:2688:699a:ce30:5897:cd3d:f999:8782]/",
			Description: "The public peer list, served inside the network",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:search",
			Title:       "Search engine for Yggdrasil",
			URL:         "http://[200:b48d:469e:c7c7:3e13:c41d:ba4d:d2b8]/",
			Description: "A search engine that indexes Yggdrasil sites",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:ipcheck",
			Title:       "IP and Port Checker",
			URL:         "http://[200:56bd:a9e9:c1fa:8f99:1d3c:3c84:6507]/",
			Description: "Check the address and ports your peer sees",
			BuiltIn:     true,
		},
		{
			ID:          "builtin:myip",
			Title:       "Show my IP address",
			URL:         "http://[320:9c1:e1fa:a105::ad]/",
			Description: "Shows the Yggdrasil address you are using",
			BuiltIn:     true,
		},
	}
}

// withBuiltInServices merges the built-in entries into the stored list without
// touching the order the user gave: a default keeps its place, a default of a
// newer build goes on top, and a built-in that was deleted stays deleted.
// The hidden list holds the defaults the user removed from the page; without it
// the merge would resurrect them on every read.
func withBuiltInServices(current []ServiceEntry, hidden []string) []ServiceEntry {
	defaults := builtInServices()
	gone := make(map[string]bool, len(hidden))
	for _, id := range hidden {
		gone[strings.TrimSpace(id)] = true
	}
	present := map[string]bool{}
	for _, entry := range current {
		present[entry.ID] = true
	}
	missing := make([]ServiceEntry, 0, len(defaults))
	builtIn := make(map[string]bool, len(defaults))
	for _, entry := range defaults {
		builtIn[entry.ID] = true
		if !present[entry.ID] && !gone[entry.ID] {
			missing = append(missing, entry)
		}
	}
	out := make([]ServiceEntry, 0, len(current)+len(missing))
	out = append(out, missing...)
	seen := map[string]bool{}
	for _, entry := range current {
		if entry.ID == "" {
			entry.ID = "user:" + directorySlug(entry.URL)
		}
		if seen[entry.ID] {
			continue
		}
		seen[entry.ID] = true
		if entry.Title == "" {
			entry.Title = entry.URL
		}
		// The window does not send the flag back, and the core owns it: a
		// saved configuration must not turn a built-in entry into a plain one.
		if builtIn[entry.ID] {
			entry.BuiltIn = true
		}
		out = append(out, entry)
	}
	return out
}

// builtInServiceIDs is the set of ids the catalogue owns.
func builtInServiceIDs() map[string]bool {
	ids := make(map[string]bool)
	for _, entry := range builtInServices() {
		ids[entry.ID] = true
	}
	return ids
}

// Services returns the whole ordered list of the Services page. The built-in
// catalogue is merged on read as well: a configuration written by an older
// build, or by a build that had no catalogue at all, still shows the eight
// entries the Android client starts with.
func (a *App) Services() []ServiceEntry {
	a.mu.Lock()
	current := a.cfg.Services
	hidden := a.cfg.HiddenServices
	a.mu.Unlock()
	return withBuiltInServices(current, hidden)
}

// HiddenServices is the list of built-in entries the user deleted. The window
// shows the restore action while it is not empty.
func (a *App) HiddenServices() []string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]string(nil), a.cfg.HiddenServices...)
}

// RestoreBuiltIns brings the deleted defaults back. The entries go on top, the
// way a catalogue entry of a newer build appears.
func (a *App) RestoreBuiltIns() error {
	a.mu.Lock()
	a.cfg.HiddenServices = nil
	a.cfg.Services = withBuiltInServices(a.cfg.Services, nil)
	cfg := a.cfg
	a.mu.Unlock()
	return cfg.save()
}

// SaveService adds a new entry or replaces one by its id. The built-in flag is
// owned by the core: a user edit never turns a built-in into a plain entry.
func (a *App) SaveService(entry ServiceEntry) (ServiceEntry, error) {
	entry.Title = strings.TrimSpace(entry.Title)
	entry.URL = strings.TrimSpace(entry.URL)
	entry.Description = strings.TrimSpace(entry.Description)
	parsed, err := url.Parse(entry.URL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return ServiceEntry{}, errors.New("the address must be an http:// or https:// URL")
	}
	if entry.Title == "" {
		entry.Title = entry.URL
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if entry.ID == "" {
		entry.ID = "user:" + strings.ReplaceAll(strings.ToLower(entry.URL), " ", "")
		entry.BuiltIn = false
	}
	// An edited entry is visible again: a default that was deleted and then
	// saved under its own id must leave the hidden list.
	a.cfg.HiddenServices = withoutString(a.cfg.HiddenServices, entry.ID)
	for index, existing := range a.cfg.Services {
		if existing.ID == entry.ID {
			entry.BuiltIn = existing.BuiltIn
			a.cfg.Services[index] = entry
			cfg := a.cfg
			return entry, cfg.save()
		}
	}
	a.cfg.Services = append(a.cfg.Services, entry)
	cfg := a.cfg
	return entry, cfg.save()
}

// RemoveService deletes one entry by its id. A built-in entry is remembered as
// hidden: the catalogue is merged on every read, so a plain deletion would last
// only until the next start.
func (a *App) RemoveService(id string) error {
	_, err := a.RemoveServices([]string{id})
	return err
}

// dnsPreset is one in-network resolver of the Yggdrasil wiki: the address, the
// place it lives in and what it filters. The Settings page lists them under
// "Available servers", the way the Android client does.
type dnsPreset struct {
	Address  string `json:"address"`
	Location string `json:"location,omitempty"`
	Note     string `json:"note,omitempty"`
}

// dnsPresets mirrors the default table of the Android client.
func dnsPresets() []dnsPreset {
	return []dnsPreset{
		{Address: "308:84:68:55::", Location: "Frankfurt, Germany", Note: "ALFIS, OpenNIC, AdGuard, Clearnet"},
		{Address: "308:25:40:bd::", Location: "Bratislava, Slovakia", Note: "ALFIS, OpenNIC, AdGuard, Clearnet"},
		{Address: "308:62:45:62::", Location: "Amsterdam, Netherlands", Note: "ALFIS, OpenNIC, AdGuard, Clearnet"},
		{Address: "308:c8:48:45::", Location: "Buffalo, USA", Note: "ALFIS, OpenNIC, AdGuard, Clearnet"},
		{Address: "215:1e33:6417:d636:c807:6985:4f4e:fda0", Location: "Ukraine", Note: "ALFIS, ClearNet"},
		{Address: "202:1d4e:724e:de52:8273:e2b5:4988:a9ba", Location: "strcat.su", Note: "Non-filtering"},
		{Address: "300:7c75:d590:c5d8::100", Location: "Melbourne, Australia", Note: "ALFIS, Clearnet, no filters"},
		{Address: "301:3423:a49b:f4e0::100", Location: "Sydney, Australia", Note: "ALFIS, Clearnet, no filters"},
		{Address: "202:cbff:6f7f:fa95:c6e9:3768:a96e:d1c8", Location: "tilde.horse", Note: "ALFIS/meshname DNS resolver"},
	}
}

// RemoveServiceByURL keeps the older request shape working: the window used to
// send the address instead of the id.
func (a *App) RemoveServiceByURL(rawURL string) error {
	rawURL = strings.TrimSpace(rawURL)
	a.mu.Lock()
	id := ""
	for _, entry := range a.cfg.Services {
		if entry.URL == rawURL {
			id = entry.ID
			break
		}
	}
	a.mu.Unlock()
	if id == "" {
		return nil
	}
	return a.RemoveService(id)
}

// RemoveServices deletes the selected entries in one go. The deleted defaults
// are remembered in the hidden list, so the catalogue does not bring them back
// on the next read or start.
func (a *App) RemoveServices(ids []string) (int, error) {
	doomed := map[string]bool{}
	for _, id := range ids {
		doomed[strings.TrimSpace(id)] = true
	}
	builtIn := builtInServiceIDs()
	a.mu.Lock()
	before := len(a.cfg.Services)
	next := make([]ServiceEntry, 0, before)
	for _, entry := range a.cfg.Services {
		if doomed[entry.ID] {
			if builtIn[entry.ID] {
				a.cfg.HiddenServices = append(a.cfg.HiddenServices, entry.ID)
			}
			continue
		}
		next = append(next, entry)
	}
	// The window merges the catalogue into the list it shows, so a default that
	// never reached the file is removed from the merged list only: it has to be
	// hidden as well, or it would come back on the next read.
	for id := range doomed {
		if builtIn[id] {
			a.cfg.HiddenServices = append(a.cfg.HiddenServices, id)
		}
	}
	a.cfg.HiddenServices = uniqueStrings(a.cfg.HiddenServices)
	a.cfg.Services = next
	cfg := a.cfg
	a.mu.Unlock()
	if err := cfg.save(); err != nil {
		return 0, err
	}
	return before - len(next), nil
}

// ReorderServices applies the order of the ids: the list keeps that sequence.
// The window orders the merged list, which can hold a default that never
// reached the file, so the catalogue is merged first: dropping an unknown id
// would leave that default on top after the next read.
func (a *App) ReorderServices(ids []string) error {
	a.mu.Lock()
	all := withBuiltInServices(a.cfg.Services, a.cfg.HiddenServices)
	byID := make(map[string]ServiceEntry, len(all))
	for _, entry := range all {
		byID[entry.ID] = entry
	}
	next := make([]ServiceEntry, 0, len(all))
	seen := map[string]bool{}
	for _, id := range ids {
		entry, ok := byID[id]
		if !ok || seen[id] {
			continue
		}
		seen[id] = true
		next = append(next, entry)
	}
	for _, entry := range all {
		if !seen[entry.ID] {
			next = append(next, entry)
		}
	}
	a.cfg.Services = next
	cfg := a.cfg
	a.mu.Unlock()
	return cfg.save()
}

// ReadDirectory fetches the web directory through the running node and parses
// the sites it lists. Without a tunnel the page is unreachable, which the
// window reports as a failure.
func (a *App) ReadDirectory() ([]ServiceEntry, error) {
	raw := a.node.FetchURL(directoryURL, 35000)
	var payload struct {
		Status int    `json:"status"`
		Body   string `json:"body"`
		Error  string `json:"error"`
	}
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		return nil, err
	}
	if payload.Error != "" {
		return nil, errors.New(payload.Error)
	}
	if payload.Status != 200 {
		return nil, errors.New("the directory did not answer")
	}
	entries := parseWebDirectory(payload.Body)
	if len(entries) == 0 {
		return nil, errors.New("the directory has no resources")
	}
	return entries, nil
}

var (
	dirRowPattern  = regexp.MustCompile(`(?is)<tr\b[^>]*>(.*?)</tr\s*>`)
	dirCellPattern = regexp.MustCompile(`(?is)<td\b[^>]*class="([^"]*)"[^>]*>(.*?)</td\s*>`)
	dirHrefPattern = regexp.MustCompile(`(?is)href\s*=\s*("([^"]*)"|'([^']*)')`)
	dirLinkPattern = regexp.MustCompile(`(?is)<h[1-6]\b[^>]*>(.*?)</h[1-6]\s*>|<a\b([^>]*)>(.*?)</a\s*>`)
	dirTags        = regexp.MustCompile(`<[^>]*>`)
	dirSpaces      = regexp.MustCompile(`\s+`)
)

// parseWebDirectory turns the directory page into address-book entries. The
// table form is tried first (the address cell, the description and the domain
// name), then a plain list of links.
func parseWebDirectory(html string) []ServiceEntry {
	var out []ServiceEntry
	seen := map[string]bool{}
	for _, row := range dirRowPattern.FindAllStringSubmatch(html, -1) {
		rowHTML := row[1]
		address := directoryAddress(rowHTML)
		if address == "" || !isDirectorySite(address) {
			continue
		}
		key := directoryKey(address)
		if seen[key] {
			continue
		}
		seen[key] = true
		description := directoryCellText(rowHTML, "descr")
		domain := directoryCellText(rowHTML, "dname")
		title := description
		if title == "" {
			title = domain
		}
		if title == "" {
			title = key
		}
		out = append(out, ServiceEntry{
			ID:          "web:" + directorySlug(address),
			Title:       title,
			URL:         address,
			Description: domain,
		})
	}
	if len(out) > 0 {
		return out
	}

	base, err := url.Parse(directoryURL)
	if err != nil {
		return nil
	}
	section := ""
	for _, match := range dirLinkPattern.FindAllStringSubmatch(html, -1) {
		if match[1] != "" {
			text := directoryText(match[1])
			if directoryIsSection(text) {
				section = text
			}
			continue
		}
		href := directoryHref(match[2])
		if href == "" || strings.HasPrefix(href, "#") || strings.HasPrefix(href, "mailto:") {
			continue
		}
		target, err := base.Parse(href)
		if err != nil {
			continue
		}
		if target.Host == base.Host && len(target.Path) > 1 {
			continue
		}
		address := target.String()
		if !isDirectorySite(address) {
			continue
		}
		key := directoryKey(address)
		if seen[key] {
			continue
		}
		seen[key] = true
		label := directoryText(match[3])
		title := label
		if title == "" || strings.HasPrefix(title, "http") {
			title = target.Host
		} else if len([]rune(title)) > 90 {
			title = string([]rune(title)[:89]) + "…"
		}
		out = append(out, ServiceEntry{
			ID:          "web:" + directorySlug(address),
			Title:       title,
			URL:         address,
			Description: section,
		})
	}
	return out
}

func directoryAddress(rowHTML string) string {
	for _, cell := range dirCellPattern.FindAllStringSubmatch(rowHTML, -1) {
		if !strings.Contains(cell[1], "addr") {
			continue
		}
		href := directoryHref(cell[2])
		if strings.HasPrefix(href, "http") {
			return href
		}
		return ""
	}
	return ""
}

func directoryCellText(rowHTML string, name string) string {
	for _, cell := range dirCellPattern.FindAllStringSubmatch(rowHTML, -1) {
		if !strings.Contains(" "+cell[1]+" ", " "+name+" ") {
			continue
		}
		if text := directoryText(cell[2]); text != "" {
			return text
		}
	}
	return ""
}

func directoryHref(attrs string) string {
	match := dirHrefPattern.FindStringSubmatch(attrs)
	if match == nil {
		return ""
	}
	value := match[2]
	if value == "" {
		value = match[3]
	}
	return strings.TrimSpace(directoryDecode(value))
}

// isDirectorySite keeps an http(s) link on a Yggdrasil address that is not an
// asset and not the directory itself.
func isDirectorySite(raw string) bool {
	parsed, err := url.Parse(raw)
	if err != nil {
		return false
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return false
	}
	host := parsed.Hostname()
	if host == "" || !isYggdrasilAddress(host) {
		return false
	}
	lower := strings.ToLower(parsed.Path)
	for _, extension := range []string{
		".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico",
		".woff", ".woff2", ".ttf",
	} {
		if strings.HasSuffix(lower, extension) {
			return false
		}
	}
	return directoryKey(raw) != directoryKey(directoryURL)
}

func directoryKey(raw string) string {
	return strings.TrimSuffix(raw, "/")
}

func directoryIsSection(text string) bool {
	if text == "" || len([]rune(text)) > 60 {
		return false
	}
	if strings.Contains(text, "//") || strings.Contains(text, "-->") {
		return false
	}
	return !strings.Contains(strings.ToLower(text), "web directory")
}

func directoryText(value string) string {
	text := dirTags.ReplaceAllString(value, " ")
	text = directoryDecode(directoryDecode(text))
	return strings.TrimSpace(dirSpaces.ReplaceAllString(text, " "))
}

func directoryDecode(value string) string {
	replacer := strings.NewReplacer(
		"&nbsp;", " ",
		"&amp;", "&",
		"&quot;", "\"",
		"&#39;", "'",
		"&apos;", "'",
		"&lt;", "<",
		"&gt;", ">",
	)
	return replacer.Replace(value)
}

func directorySlug(raw string) string {
	value := strings.TrimPrefix(strings.TrimPrefix(raw, "https://"), "http://")
	var builder strings.Builder
	lastDash := false
	for _, ch := range strings.ToLower(value) {
		switch {
		case ch >= 'a' && ch <= 'z', ch >= '0' && ch <= '9':
			builder.WriteRune(ch)
			lastDash = false
		default:
			if !lastDash {
				builder.WriteByte('-')
				lastDash = true
			}
		}
	}
	return strings.Trim(builder.String(), "-")
}

// uniquePeers drops empty and repeated URIs while keeping the order.
func uniquePeers(list []string) []string {
	out := make([]string, 0, len(list))
	seen := map[string]bool{}
	for _, uri := range list {
		uri = strings.TrimSpace(uri)
		if uri == "" || seen[uri] {
			continue
		}
		seen[uri] = true
		out = append(out, uri)
	}
	return out
}

// uniqueStrings drops empty and repeated values while keeping the order.
func uniqueStrings(list []string) []string {
	out := make([]string, 0, len(list))
	seen := map[string]bool{}
	for _, value := range list {
		value = strings.TrimSpace(value)
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		out = append(out, value)
	}
	return out
}

// withoutString returns the list without one value.
func withoutString(list []string, value string) []string {
	out := make([]string, 0, len(list))
	for _, item := range list {
		if item != value {
			out = append(out, item)
		}
	}
	return out
}
