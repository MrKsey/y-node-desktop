package desktop

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Dialer opens one connection on behalf of a proxied client.
type Dialer func(ctx context.Context, network, address string) (net.Conn, error)

// Stats counts what the local proxy moved. The counters live in the core
// process, so the window can show the same figures after a restart of the UI.
type Stats struct {
	Up        atomic.Uint64
	Down      atomic.Uint64
	Open      atomic.Int64
	TotalOpen atomic.Uint64
}

// Proxy is the local HTTP and SOCKS5 endpoint of the desktop app. Both
// listeners use the same dialer, so a browser configured for the HTTP proxy and
// an app configured for SOCKS5 leave through the same node and the same exit.
type Proxy struct {
	httpServer *http.Server
	httpLn     net.Listener
	socksLn    net.Listener
	dial       Dialer
	log        *LogBuffer
	stats      *Stats
	transport  *http.Transport
	wg         sync.WaitGroup
	closeOnce  sync.Once
}

func NewProxy(dial Dialer, log *LogBuffer, stats *Stats) *Proxy {
	p := &Proxy{dial: dial, log: log, stats: stats}
	p.transport = &http.Transport{
		Proxy:               nil,
		DialContext:         dial,
		DisableKeepAlives:   true,
		ForceAttemptHTTP2:   false,
		TLSHandshakeTimeout: 15 * time.Second,
		IdleConnTimeout:     30 * time.Second,
	}
	return p
}

// Start binds both listeners. A port that is already in use is reported before
// the node is announced as connected.
func (p *Proxy) Start(bind string, httpPort, socksPort int) error {
	if bind == "" {
		bind = "127.0.0.1"
	}
	httpAddr := net.JoinHostPort(bind, strconv.Itoa(httpPort))
	httpLn, err := net.Listen("tcp", httpAddr)
	if err != nil {
		return fmt.Errorf("HTTP proxy on %s: %w", httpAddr, err)
	}
	socksAddr := net.JoinHostPort(bind, strconv.Itoa(socksPort))
	socksLn, err := net.Listen("tcp", socksAddr)
	if err != nil {
		_ = httpLn.Close()
		return fmt.Errorf("SOCKS5 proxy on %s: %w", socksAddr, err)
	}

	p.httpLn = httpLn
	p.socksLn = socksLn
	p.httpServer = &http.Server{
		Handler:           p,
		ReadHeaderTimeout: 20 * time.Second,
	}

	p.wg.Add(2)
	go func() {
		defer p.wg.Done()
		if err := p.httpServer.Serve(httpLn); err != nil && !errors.Is(err, http.ErrServerClosed) {
			p.log.Warnf("HTTP proxy stopped: %v", err)
		}
	}()
	go func() {
		defer p.wg.Done()
		p.serveSocks(socksLn)
	}()

	p.log.Infof("proxy listening: HTTP %s, SOCKS5 %s", httpAddr, socksAddr)
	return nil
}

// Stop closes both listeners and every connection that is still open.
func (p *Proxy) Stop() {
	p.closeOnce.Do(func() {
		if p.httpServer != nil {
			_ = p.httpServer.Close()
		}
		if p.httpLn != nil {
			_ = p.httpLn.Close()
		}
		if p.socksLn != nil {
			_ = p.socksLn.Close()
		}
		p.transport.CloseIdleConnections()
		p.wg.Wait()
	})
}

// ---------------------------------------------------------------------------
// HTTP proxy
// ---------------------------------------------------------------------------

func (p *Proxy) ServeHTTP(rw http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		p.handleConnect(rw, r)
		return
	}
	p.handleForward(rw, r)
}

func (p *Proxy) handleConnect(rw http.ResponseWriter, r *http.Request) {
	target := r.Host
	if !strings.Contains(target, ":") {
		target += ":443"
	}
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	upstream, err := p.dial(ctx, "tcp", target)
	cancel()
	if err != nil {
		// A browser opens a preconnect and drops it again, and a page that is
		// already loaded cancels the rest: the client is gone, the tunnel is
		// fine, so the line is not a warning about the exit node.
		if r.Context().Err() != nil {
			p.log.Log("debug", fmt.Sprintf("CONNECT %s: the client gave up", target))
		} else {
			p.log.Warnf("CONNECT %s: %v", target, err)
		}
		http.Error(rw, "cannot connect: "+err.Error(), http.StatusBadGateway)
		return
	}

	hijacker, ok := rw.(http.Hijacker)
	if !ok {
		_ = upstream.Close()
		http.Error(rw, "the connection cannot be upgraded", http.StatusInternalServerError)
		return
	}
	client, buffered, err := hijacker.Hijack()
	if err != nil {
		_ = upstream.Close()
		return
	}
	if _, err := buffered.WriteString("HTTP/1.1 200 Connection established\r\n\r\n"); err != nil {
		_ = client.Close()
		_ = upstream.Close()
		return
	}
	_ = buffered.Flush()

	p.track(client, upstream)
}

func (p *Proxy) handleForward(rw http.ResponseWriter, r *http.Request) {
	if r.URL == nil || !r.URL.IsAbs() {
		http.Error(rw, "this is a proxy: send an absolute URL", http.StatusBadRequest)
		return
	}
	out := r.Clone(r.Context())
	out.RequestURI = ""
	removeHopByHop(out.Header)
	out.Header.Del("Proxy-Connection")
	out.Header.Del("Proxy-Authorization")
	if out.URL.Scheme == "" {
		out.URL.Scheme = "http"
	}

	response, err := p.transport.RoundTrip(out)
	if err != nil {
		if r.Context().Err() != nil || isClientAbort(err) {
			p.log.Log("debug", fmt.Sprintf("%s %s: the client gave up", r.Method, r.URL.Host))
		} else {
			p.log.Warnf("%s %s: %v", r.Method, r.URL.Host, err)
		}
		http.Error(rw, "cannot reach the destination: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer response.Body.Close()

	removeHopByHop(response.Header)
	for name, values := range response.Header {
		for _, value := range values {
			rw.Header().Add(name, value)
		}
	}
	rw.WriteHeader(response.StatusCode)
	if _, err := io.Copy(rw, response.Body); err != nil {
		// The browser closes a tab or cancels a download while the body is
		// still being copied. Windows reports that as "wsasend: An existing
		// connection was forcibly closed", which looked like a tunnel failure
		// in the log although the client was simply gone.
		if r.Context().Err() != nil || isClientAbort(err) {
			p.log.Log("debug", fmt.Sprintf("response body %s: the client gave up", r.URL.Host))
		} else {
			p.log.Warnf("response body %s: %v", r.URL.Host, err)
		}
	}
}

// isClientAbort reports whether a copy error comes from the local client
// closing its side of the connection rather than from the destination.
func isClientAbort(err error) bool {
	text := strings.ToLower(err.Error())
	for _, marker := range []string{
		"wsasend", "forcibly closed", "broken pipe", "connection reset",
		"connection aborted", "use of closed network connection",
	} {
		if strings.Contains(text, marker) {
			return true
		}
	}
	return false
}

func removeHopByHop(header http.Header) {
	for _, name := range []string{
		"Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization",
		"Te", "Trailer", "Transfer-Encoding", "Upgrade",
	} {
		header.Del(name)
	}
}

// ---------------------------------------------------------------------------
// SOCKS5
// ---------------------------------------------------------------------------

func (p *Proxy) serveSocks(listener net.Listener) {
	for {
		conn, err := listener.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			p.log.Warnf("SOCKS5 accept: %v", err)
			continue
		}
		p.wg.Add(1)
		go func() {
			defer p.wg.Done()
			p.handleSocks(conn)
		}()
	}
}

func (p *Proxy) handleSocks(conn net.Conn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))

	head := make([]byte, 2)
	if _, err := io.ReadFull(conn, head); err != nil || head[0] != 5 {
		return
	}
	methods := make([]byte, int(head[1]))
	if _, err := io.ReadFull(conn, methods); err != nil {
		return
	}
	if _, err := conn.Write([]byte{5, 0}); err != nil {
		return
	}

	request := make([]byte, 4)
	if _, err := io.ReadFull(conn, request); err != nil {
		return
	}
	if request[0] != 5 {
		return
	}
	command := request[1]
	atyp := request[3]

	var host string
	switch atyp {
	case 1:
		raw := make([]byte, 4)
		if _, err := io.ReadFull(conn, raw); err != nil {
			return
		}
		host = net.IP(raw).String()
	case 3:
		length := make([]byte, 1)
		if _, err := io.ReadFull(conn, length); err != nil {
			return
		}
		raw := make([]byte, int(length[0]))
		if _, err := io.ReadFull(conn, raw); err != nil {
			return
		}
		host = string(raw)
	case 4:
		raw := make([]byte, 16)
		if _, err := io.ReadFull(conn, raw); err != nil {
			return
		}
		host = net.IP(raw).String()
	default:
		_, _ = conn.Write([]byte{5, 8, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	portRaw := make([]byte, 2)
	if _, err := io.ReadFull(conn, portRaw); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(portRaw)
	target := net.JoinHostPort(host, strconv.Itoa(int(port)))

	if command != 1 {
		// UDP ASSOCIATE and BIND are not part of the desktop MVP: the HTTP
		// proxy already carries DNS and QUIC for the applications that need it.
		_, _ = conn.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	upstream, err := p.dial(ctx, "tcp", target)
	cancel()
	if err != nil {
		p.log.Warnf("SOCKS5 %s: %v", target, err)
		_, _ = conn.Write([]byte{5, 5, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	if _, err := conn.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		_ = upstream.Close()
		return
	}
	_ = conn.SetDeadline(time.Time{})
	p.track(conn, upstream)
}

// ---------------------------------------------------------------------------
// Relay
// ---------------------------------------------------------------------------

func (p *Proxy) track(client, upstream net.Conn) {
	p.stats.Open.Add(1)
	p.stats.TotalOpen.Add(1)
	defer p.stats.Open.Add(-1)
	defer client.Close()
	defer upstream.Close()

	down := &countingReader{conn: upstream, counter: &p.stats.Down}
	up := &countingReader{conn: client, counter: &p.stats.Up}

	done := make(chan struct{}, 2)
	go func() {
		_, _ = io.Copy(client, down)
		closeWrite(client)
		done <- struct{}{}
	}()
	go func() {
		_, _ = io.Copy(upstream, up)
		closeWrite(upstream)
		done <- struct{}{}
	}()
	<-done
	<-done
}

type countingReader struct {
	conn    net.Conn
	counter *atomic.Uint64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.conn.Read(p)
	if n > 0 {
		c.counter.Add(uint64(n))
	}
	return n, err
}

func closeWrite(conn net.Conn) {
	if closer, ok := conn.(interface{ CloseWrite() error }); ok {
		_ = closer.CloseWrite()
	}
}
