package yggnode

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	// dnsVIP is the address the tunnel hands to Android as its resolver. It is
	// not assigned to the interface: packets to it arrive through the TUN and
	// are answered by the router inside the forwarding stack.
	dnsVIP = "10.111.222.2"

	dnsVIPPort = 53
)

type dnsCacheEntry struct {
	response []byte
	expires  time.Time
}

// dnsRouter splits name resolution between the three networks the app can see:
// .ygg names go to the Yggdrasil resolvers, local names go to the DNS servers
// of the real network, and everything else goes through the exit node.
type dnsRouter struct {
	mu     sync.Mutex
	cache  map[string]dnsCacheEntry
	exit   *exitManager
	inner  *internalNet
	direct *directDialer
	log    *goLogger
}

func newDNSRouter(exit *exitManager, inner *internalNet, direct *directDialer, log *goLogger) *dnsRouter {
	return &dnsRouter{
		cache:  make(map[string]dnsCacheEntry),
		exit:   exit,
		inner:  inner,
		direct: direct,
		log:    log,
	}
}

func isDNSVIP(addr net.IP) bool {
	return addr != nil && addr.To4() != nil && addr.To4().Equal(net.ParseIP(dnsVIP).To4())
}

// handle resolves one DNS message and returns the response. A nil result means
// the query was malformed and must be dropped.
func (r *dnsRouter) handle(query []byte) []byte {
	if len(query) < 12 {
		return nil
	}
	name, qtype, ok := dnsQuestion(query)
	if !ok {
		return nil
	}
	key := strings.ToLower(name) + "|" + strconv.Itoa(int(qtype))
	if cached := r.lookup(key); cached != nil {
		return cached
	}

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	var response []byte
	// cacheable is false for an answer that came from a fallback path: such an
	// answer describes another network than the one the traffic uses, and
	// keeping it for the TTL of the record breaks the site for minutes after
	// the real resolver recovers.
	cacheable := true
	switch r.exit.config().dnsMode() {
	case "system":
		// The user asked for the resolver of the operating system, like the
		// "system" mode of the Android client.
		response = r.resolveSystem(ctx, query)
	case "custom":
		response = r.resolveCustom(ctx, query)
	default:
		switch {
		case isYggName(name):
			response = r.resolveYgg(ctx, query)
		case r.isLocalName(name):
			response = r.resolveLocal(ctx, query)
		default:
			response, cacheable = r.resolveOrdinary(ctx, query)
		}
	}
	if len(response) == 0 {
		response = servfail(query)
	}
	// An error answer describes a moment, not the site: a resolver that is
	// momentarily out of quota answers SERVFAIL, and caching that answer hides
	// the working resolvers for the whole negative TTL. Only a real answer is
	// kept; a "name does not exist" is kept for a few seconds because every
	// click on a dead link would otherwise repeat the lookup.
	if len(response) > 0 && cacheable {
		switch dnsRcode(response) {
		case 0:
			r.store(key, response)
		case dnsRcodeNameError:
			r.storeFor(key, response, 5*time.Second)
		}
	}
	return response
}

// dnsRcodeNameError is the "no such name" answer of a resolver.
const dnsRcodeNameError = 3

// dnsRcode returns the response code of a DNS message, or -1 when the message
// is not a response at all.
func dnsRcode(msg []byte) int {
	if len(msg) < 12 || binary.BigEndian.Uint16(msg[2:4])&0x8000 == 0 {
		return -1
	}
	return int(binary.BigEndian.Uint16(msg[2:4]) & 0x000F)
}

// dnsUsable reports whether a resolver returned a real answer. A SERVFAIL or a
// REFUSED from one server says nothing about the name: the next resolver of the
// list has to be asked.
func dnsUsable(msg []byte) bool {
	return len(msg) >= 12 && dnsRcode(msg) == 0
}

func (r *dnsRouter) isLocalName(name string) bool {
	cfg := r.exit.config()
	if !cfg.LocalDNS {
		return false
	}
	lower := strings.ToLower(strings.TrimSuffix(name, "."))
	if lower == "localhost" || strings.HasSuffix(lower, ".localhost") {
		return true
	}
	if !strings.Contains(lower, ".") {
		return true // a single-label name is always a local one
	}
	for _, suffix := range []string{
		".local", ".lan", ".home", ".home.arpa", ".internal",
		".intranet", ".localdomain", ".arpa", ".box",
	} {
		if strings.HasSuffix(lower, suffix) {
			return true
		}
	}
	return false
}

func isYggName(name string) bool {
	lower := strings.ToLower(strings.TrimSuffix(name, "."))
	return lower == "ygg" || strings.HasSuffix(lower, ".ygg")
}

// resolveCustom asks the servers the user configured in the "custom" DNS mode.
// A Yggdrasil address is queried through the node, an ordinary one directly, so
// the same list can hold both kinds.
func (r *dnsRouter) resolveCustom(ctx context.Context, query []byte) []byte {
	cfg := r.exit.config()
	stageCtx, cancel := context.WithTimeout(ctx, dnsStageTimeout)
	response := raceResolvers(stageCtx, cfg.YggDNS, query, func(ctx context.Context, server string, query []byte) ([]byte, error) {
		if host, _, splitErr := net.SplitHostPort(dnsEndpoint(server)); splitErr == nil {
			if ip := net.ParseIP(host); ip != nil && yggRange.Contains(ip) {
				return r.queryInner(ctx, server, query)
			}
		}
		return r.queryDirect(ctx, server, query)
	}, r.log, "custom")
	cancel()
	if dnsUsable(response) {
		return response
	}
	return r.resolveSystem(ctx, query)
}

func (r *dnsRouter) resolveYgg(ctx context.Context, query []byte) []byte {
	cfg := r.exit.config()
	if r.inner == nil {
		return nil
	}
	stageCtx, cancel := context.WithTimeout(ctx, dnsStageTimeout)
	defer cancel()
	return raceResolvers(stageCtx, cfg.YggDNS, query, r.queryInner, r.log, "ygg")
}

func (r *dnsRouter) resolveLocal(ctx context.Context, query []byte) []byte {
	cfg := r.exit.config()
	if len(cfg.SystemDNS) == 0 {
		return nil
	}
	stageCtx, cancel := context.WithTimeout(ctx, dnsStageTimeout)
	defer cancel()
	return raceResolvers(stageCtx, cfg.SystemDNS, query, r.queryDirect, r.log, "local")
}

// resolveOrdinary resolves a public name. The second result says whether the
// answer came from the exit resolver: only that answer matches the path the
// traffic takes, so only it may be cached. A fallback answer comes from the
// local network while the connection still leaves through the exit, and a site
// behind a CDN rejects such a pair with "revalidate your DNS cache".
func (r *dnsRouter) resolveOrdinary(ctx context.Context, query []byte) ([]byte, bool) {
	cfg := r.exit.config()
	// The exit resolver is optional: only ask the exit when the user configured
	// one. Otherwise ordinary names go to the system resolvers directly, which
	// is what keeps browsers working while an exit node is enabled but has no
	// DNS server (or is not reachable yet).
	exitPath := cfg.Enabled && len(cfg.Profiles) > 0 && len(cfg.DNS) > 0 && r.exit != nil
	// errorAnswer is the last answer with a non-zero response code. It is only
	// returned when every resolver failed: an error from one server must not
	// hide the answer of the next one, and it must never be cached.
	var errorAnswer []byte
	if exitPath {
		exitCtx, exitCancel := context.WithTimeout(ctx, dnsStageTimeout)
		response := raceResolvers(exitCtx, cfg.DNS, query, r.queryExit, r.log, "exit")
		exitCancel()
		if dnsUsable(response) {
			return response, true
		}
		if len(response) > 0 {
			errorAnswer = response
		}
		if !cfg.FallbackDirect {
			return errorAnswer, false
		}
		r.log.emit("warn", "dns: the exit resolver is unavailable, resolving directly")
	}
	// cfg.DNS holds the resolvers reached through the exit; the local ones are
	// cfg.SystemDNS. A failed exit lookup must fall back to the local network,
	// never to the exit's own list: those addresses belong to the relay, and
	// asking 1.1.1.1 from this network both leaks the query and gets the answer
	// of whatever resolver the provider runs on port 53. That answer was then
	// logged as "direct resolver answered name does not exist", which looks like
	// a broken exit DNS while the exit was simply down.
	directCtx, directCancel := context.WithTimeout(ctx, dnsStageTimeout)
	response := raceResolvers(directCtx, cfg.SystemDNS, query, r.queryDirect, r.log, "direct")
	directCancel()
	if dnsUsable(response) {
		return response, !exitPath
	}
	if len(response) > 0 {
		errorAnswer = response
	}
	// The exit list (cfg.DNS) is the only public resolver list a fresh install
	// has: the resolvers of the real network are unknown, and the one of the
	// provider may refuse a name that exists only as a Yggdrasil address (the
	// forum of the network is a CNAME to an AAAA record). Without an exit
	// those servers are ordinary public resolvers, so asking them directly is
	// the same path the Android client takes.
	if (!exitPath || len(cfg.SystemDNS) == 0) && len(cfg.DNS) > 0 {
		publicCtx, publicCancel := context.WithTimeout(ctx, dnsStageTimeout)
		response := raceResolvers(publicCtx, cfg.DNS, query, r.queryDirect, r.log, "public")
		publicCancel()
		if dnsUsable(response) {
			return response, false
		}
		if len(response) > 0 && errorAnswer == nil {
			errorAnswer = response
		}
	}
	// The configured resolvers may be blocked by the local network (a router
	// that hijacks port 53, a hotel Wi-Fi). The operating system already knows
	// which servers work, so the last resort is the system resolver.
	if response := r.resolveSystem(ctx, query); len(response) > 0 {
		return response, !exitPath
	}
	return errorAnswer, false
}

// dnsStageTimeout bounds one group of resolvers. The groups are tried in turn
// (the exit, then the local network, then the system resolver), so a dead
// server in one group must not eat the budget of the next one. Resolvers inside
// a group are asked in parallel: the first usable answer wins, and a resolver
// that is down no longer delays every name by its timeout.
const dnsStageTimeout = 3 * time.Second

// resolverResult is one answer of the parallel race.
type resolverResult struct {
	server   string
	response []byte
	err      error
}

// raceResolvers asks every server of one group at once and returns the first
// usable answer. An error answer is kept as a fallback for the caller: a
// SERVFAIL from every server is still more useful than a synthetic timeout.
func raceResolvers(
	ctx context.Context,
	servers []string,
	query []byte,
	lookup func(context.Context, string, []byte) ([]byte, error),
	log *goLogger,
	kind string,
) []byte {
	if len(servers) == 0 {
		return nil
	}
	raceCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	results := make(chan resolverResult, len(servers))
	for _, server := range servers {
		server := server
		go func() {
			response, err := lookup(raceCtx, server, query)
			results <- resolverResult{server: server, response: response, err: err}
		}()
	}
	var errorAnswer []byte
	for range servers {
		select {
		case <-ctx.Done():
			return errorAnswer
		case result := <-results:
			switch {
			case result.err != nil:
				log.emit("debug", "dns: %s resolver %s: %v", kind, result.server, result.err)
			case dnsUsable(result.response):
				return result.response
			case len(result.response) > 0:
				log.emit("debug", "dns: %s resolver %s answered %s", kind, result.server, dnsRcodeText(result.response))
				if errorAnswer == nil {
					errorAnswer = result.response
				}
			}
		}
	}
	return errorAnswer
}

// dnsRcodeText names a response code for the log. The log is the only place a
// user can see why a name did not resolve: "no answer" of the proxy is the
// consequence, not the reason.
func dnsRcodeText(msg []byte) string {
	switch dnsRcode(msg) {
	case 1:
		return "a malformed query"
	case 2:
		return "server failure"
	case 3:
		return "name does not exist"
	case 4:
		return "query type not supported"
	case 5:
		return "query refused"
	default:
		return "an error"
	}
}

// resolveSystem resolves one name with the operating system resolver and turns
// the answer into a DNS message. It is the fallback that keeps ordinary sites
// working when the configured resolvers are unreachable.
func (r *dnsRouter) resolveSystem(ctx context.Context, query []byte) []byte {
	name, qtype, ok := dnsQuestion(query)
	if !ok || (qtype != dnsTypeA && qtype != dnsTypeAAAA) {
		return nil
	}
	addrs, err := net.DefaultResolver.LookupIPAddr(ctx, name)
	if err != nil {
		r.log.emit("debug", "dns: system resolver %s: %v", name, err)
		return nil
	}
	ips := make([]net.IP, 0, len(addrs))
	for _, addr := range addrs {
		if qtype == dnsTypeA && addr.IP.To4() != nil {
			ips = append(ips, addr.IP.To4())
		}
		if qtype == dnsTypeAAAA && addr.IP.To4() == nil {
			ips = append(ips, addr.IP.To16())
		}
	}
	if len(ips) == 0 {
		return nil
	}
	r.log.emit("debug", "dns: system resolver answered %s", name)
	return dnsAnswerMessage(query, qtype, ips)
}

// dnsAnswerMessage builds a response for one query from a list of addresses. The
// question section is copied from the request, so the caller matches the answer
// by the id and the name it sent.
func dnsAnswerMessage(query []byte, qtype uint16, ips []net.IP) []byte {
	if len(query) < 12 {
		return nil
	}
	questionEnd := 12
	for {
		if questionEnd >= len(query) {
			return nil
		}
		length := int(query[questionEnd])
		if length == 0 {
			questionEnd++
			break
		}
		if length&0xC0 != 0 {
			return nil
		}
		questionEnd += 1 + length
	}
	questionEnd += 4 // QTYPE + QCLASS
	if questionEnd > len(query) {
		return nil
	}
	response := make([]byte, 0, questionEnd+16*len(ips))
	response = append(response, query[:questionEnd]...)
	flags := binary.BigEndian.Uint16(query[2:4])
	flags |= 0x8000 // QR
	flags |= 0x0080 // RA
	flags &^= 0x000F
	binary.BigEndian.PutUint16(response[2:4], flags)
	binary.BigEndian.PutUint16(response[6:8], uint16(len(ips)))
	binary.BigEndian.PutUint16(response[8:10], 0)
	binary.BigEndian.PutUint16(response[10:12], 0)
	for _, ip := range ips {
		raw := ip.To4()
		recordType := uint16(dnsTypeA)
		if qtype == dnsTypeAAAA {
			raw = ip.To16()
			recordType = dnsTypeAAAA
		}
		if raw == nil {
			continue
		}
		var head [12]byte
		binary.BigEndian.PutUint16(head[0:2], 0xC00C) // pointer to the question name
		binary.BigEndian.PutUint16(head[2:4], recordType)
		binary.BigEndian.PutUint16(head[4:6], 1) // class IN
		binary.BigEndian.PutUint32(head[6:10], 60)
		binary.BigEndian.PutUint16(head[10:12], uint16(len(raw)))
		response = append(response, head[:]...)
		response = append(response, raw...)
	}
	return response
}

func (r *dnsRouter) queryInner(ctx context.Context, server string, query []byte) ([]byte, error) {
	return queryDNSUpstream(ctx, func(ctx context.Context, network, address string) (net.Conn, error) {
		return r.inner.dialContext(ctx, network, address)
	}, server, query)
}

func (r *dnsRouter) queryDirect(ctx context.Context, server string, query []byte) ([]byte, error) {
	return queryDNSUpstream(ctx, r.direct.DialContext, server, query)
}

func (r *dnsRouter) queryExit(ctx context.Context, server string, query []byte) ([]byte, error) {
	address := dnsEndpoint(server)
	// A resolver that lives on a Yggdrasil address (an X-Node publishes its
	// Alfis server that way) is reached through the node itself. The exit's
	// relay only carries ordinary internet destinations, and a Yggdrasil
	// address sent to the system dialer is simply unreachable.
	if host, _, err := net.SplitHostPort(address); err == nil {
		if ip := net.ParseIP(host); ip != nil && yggRange.Contains(ip) {
			return r.queryInner(ctx, server, query)
		}
	}
	if r.exit.udpEnabled() {
		response, err := queryDNSDatagram(ctx, func(ctx context.Context, _, address string) (net.Conn, error) {
			return r.exit.DialContext(ctx, "udp", address)
		}, address, query)
		switch {
		case err != nil:
			r.log.emit("debug", "dns: exit UDP resolver %s: %v", server, err)
		case len(response) >= 12 && binary.BigEndian.Uint16(response[2:4])&0x0200 == 0:
			return response, nil
		}
		// A truncated answer, or no datagram at all: the same query goes over
		// TCP, which the exit always carries.
	}
	return queryDNSNetwork(ctx, func(ctx context.Context, _, address string) (net.Conn, error) {
		return r.exit.DialContext(ctx, "tcp", address)
	}, "tcp", address, query)
}

// queryDNSDatagram sends one query over a datagram socket and waits for the
// answer with the matching transaction id. A shared exit relay can deliver the
// answer of another in-flight query to the same server, and that answer must
// not be cached under this question.
func queryDNSDatagram(
	ctx context.Context,
	dial func(ctx context.Context, network, address string) (net.Conn, error),
	address string,
	query []byte,
) ([]byte, error) {
	conn, err := dial(ctx, "udp", address)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	} else {
		_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	}
	if _, err := conn.Write(query); err != nil {
		return nil, err
	}
	buf := make([]byte, 65535)
	for {
		n, err := conn.Read(buf)
		if err != nil {
			return nil, err
		}
		if n < 12 {
			continue
		}
		if len(query) >= 2 && !bytes.Equal(buf[0:2], query[0:2]) {
			continue
		}
		if !sameDNSQuestion(query, buf[:n]) {
			continue
		}
		return append([]byte(nil), buf[:n]...), nil
	}
}

// queryDNSUpstream sends a UDP query and retries over TCP when the answer is
// truncated. The exit path only speaks TCP, so its dial function ignores the
// network argument.
func queryDNSUpstream(
	ctx context.Context,
	dial func(ctx context.Context, network, address string) (net.Conn, error),
	server string,
	query []byte,
) ([]byte, error) {
	address := dnsEndpoint(server)
	response, err := queryDNSNetwork(ctx, dial, "udp", address, query)
	if err != nil {
		return nil, err
	}
	if len(response) >= 4 && binary.BigEndian.Uint16(response[2:4])&0x0200 != 0 {
		return queryDNSNetwork(ctx, dial, "tcp", address, query)
	}
	return response, nil
}

// dnsEndpoint returns the dial address of a resolver. Servers are normally
// stored as bare addresses and queried on port 53; an exit node that publishes
// its resolver on another port sends it as `[address]:port`, which already
// carries the port.
func dnsEndpoint(server string) string {
	if host, _, err := net.SplitHostPort(server); err == nil && host != "" {
		return server
	}
	return net.JoinHostPort(server, "53")
}

func queryDNSNetwork(
	ctx context.Context,
	dial func(ctx context.Context, network, address string) (net.Conn, error),
	network, address string,
	query []byte,
) ([]byte, error) {
	conn, err := dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	} else {
		_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	}
	if network == "tcp" {
		return queryTCPConn(conn, query)
	}
	if _, err := conn.Write(query); err != nil {
		return nil, err
	}
	buf := make([]byte, 4096)
	n, err := conn.Read(buf)
	if err != nil {
		return nil, err
	}
	// A resolver on a hijacked port 53, or a shared exit relay, can answer a
	// question this client never asked. Such a message must not become the
	// address of the name: the browser would connect to the wrong site and
	// fail on the certificate.
	if !sameDNSQuestion(query, buf[:n]) {
		return nil, errors.New("the resolver answered another question")
	}
	return append([]byte(nil), buf[:n]...), nil
}

// sameDNSQuestion reports whether a reply carries the same question as the
// query. Names are compared without case and without the root dot, because a
// resolver is free to echo them in its own form.
func sameDNSQuestion(query, reply []byte) bool {
	queryName, queryType, ok := dnsQuestion(query)
	if !ok {
		return false
	}
	replyName, replyType, ok := dnsQuestion(reply)
	if !ok {
		return false
	}
	if queryType != replyType {
		return false
	}
	return strings.EqualFold(
		strings.TrimSuffix(queryName, "."),
		strings.TrimSuffix(replyName, "."),
	)
}

func queryTCPConn(conn net.Conn, query []byte) ([]byte, error) {
	frame := make([]byte, 2+len(query))
	binary.BigEndian.PutUint16(frame[0:2], uint16(len(query)))
	copy(frame[2:], query)
	if _, err := conn.Write(frame); err != nil {
		return nil, err
	}
	var size [2]byte
	if _, err := io.ReadFull(conn, size[:]); err != nil {
		return nil, err
	}
	length := int(binary.BigEndian.Uint16(size[:]))
	if length < 12 || length > 65535 {
		return nil, errors.New("bad DNS response length")
	}
	response := make([]byte, length)
	if _, err := io.ReadFull(conn, response); err != nil {
		return nil, err
	}
	if !sameDNSQuestion(query, response) {
		return nil, errors.New("the resolver answered another question")
	}
	return response, nil
}

// dnsQuestion returns the first QNAME and QTYPE.
func dnsQuestion(msg []byte) (string, uint16, bool) {
	if len(msg) < 12 {
		return "", 0, false
	}
	if binary.BigEndian.Uint16(msg[4:6]) == 0 {
		return "", 0, false
	}
	offset := 12
	var labels []string
	for {
		if offset >= len(msg) {
			return "", 0, false
		}
		length := int(msg[offset])
		if length == 0 {
			offset++
			break
		}
		if length&0xC0 != 0 {
			return "", 0, false
		}
		if offset+1+length > len(msg) {
			return "", 0, false
		}
		labels = append(labels, string(msg[offset+1:offset+1+length]))
		offset += 1 + length
	}
	if offset+4 > len(msg) {
		return "", 0, false
	}
	return strings.Join(labels, "."), binary.BigEndian.Uint16(msg[offset : offset+2]), true
}

// servfail turns a query into a SERVFAIL response, preserving the id and the
// question so the client can match it.
func servfail(query []byte) []byte {
	if len(query) < 12 {
		return nil
	}
	response := append([]byte(nil), query...)
	flags := binary.BigEndian.Uint16(response[2:4])
	flags |= 0x8000 // QR
	flags |= 0x0080 // RA
	flags = (flags &^ 0x000F) | 2
	binary.BigEndian.PutUint16(response[2:4], flags)
	binary.BigEndian.PutUint16(response[6:8], 0)
	binary.BigEndian.PutUint16(response[8:10], 0)
	binary.BigEndian.PutUint16(response[10:12], 0)
	return response
}

func (r *dnsRouter) lookup(key string) []byte {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.cache[key]
	if !ok || time.Now().After(entry.expires) {
		if ok {
			delete(r.cache, key)
		}
		return nil
	}
	return append([]byte(nil), entry.response...)
}

func (r *dnsRouter) store(key string, response []byte) {
	r.storeWithTTL(key, response, dnsTTL(response))
}

// storeFor keeps an answer for a fixed time. The "no such name" answer uses it:
// the TTL of a negative answer belongs to the authority section, which the
// helper below does not read.
func (r *dnsRouter) storeFor(key string, response []byte, ttl time.Duration) {
	r.storeWithTTL(key, response, ttl)
}

func (r *dnsRouter) storeWithTTL(key string, response []byte, ttl time.Duration) {
	if ttl <= 0 {
		return
	}
	if ttl > 10*time.Minute {
		ttl = 10 * time.Minute
	}
	if ttl < 5*time.Second {
		ttl = 5 * time.Second
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.cache) > 1024 {
		now := time.Now()
		for k, entry := range r.cache {
			if now.After(entry.expires) {
				delete(r.cache, k)
			}
		}
		if len(r.cache) > 1024 {
			for k := range r.cache {
				delete(r.cache, k)
				if len(r.cache) <= 1024 {
					break
				}
			}
		}
	}
	r.cache[key] = dnsCacheEntry{
		response: append([]byte(nil), response...),
		expires:  time.Now().Add(ttl),
	}
}

func (r *dnsRouter) clearCache() {
	r.mu.Lock()
	r.cache = make(map[string]dnsCacheEntry)
	r.mu.Unlock()
}

// dnsTTL returns the smallest TTL of the answer section, or a short negative
// TTL for an error response.
func dnsTTL(msg []byte) time.Duration {
	if len(msg) < 12 {
		return 0
	}
	flags := binary.BigEndian.Uint16(msg[2:4])
	if flags&0x8000 == 0 {
		return 0
	}
	rcode := int(flags & 0x000F)
	questions := int(binary.BigEndian.Uint16(msg[4:6]))
	answers := int(binary.BigEndian.Uint16(msg[6:8]))
	offset := 12
	for i := 0; i < questions; i++ {
		next, ok := skipDNSName(msg, offset)
		if !ok || next+4 > len(msg) {
			return 0
		}
		offset = next + 4
	}
	if rcode != 0 {
		// An error answer is not cached: see handle(). A resolver that fails
		// for a second must not hide a working one for the next half a minute.
		return 0
	}
	minimum := uint32(0)
	for i := 0; i < answers; i++ {
		next, ok := skipDNSName(msg, offset)
		if !ok || next+10 > len(msg) {
			break
		}
		ttl := binary.BigEndian.Uint32(msg[next+4 : next+8])
		length := int(binary.BigEndian.Uint16(msg[next+8 : next+10]))
		if minimum == 0 || ttl < minimum {
			minimum = ttl
		}
		offset = next + 10 + length
		if offset > len(msg) {
			break
		}
	}
	if minimum == 0 {
		return 0
	}
	return time.Duration(minimum) * time.Second
}

func (r *dnsRouter) status() map[string]any {
	r.mu.Lock()
	entries := len(r.cache)
	r.mu.Unlock()
	return map[string]any{
		"address": dnsVIP,
		"cache":   entries,
	}
}
