// Command y-node-core is the background process of the Y-Node desktop app. It
// owns the Yggdrasil node, the local proxy and the per-user system proxy, and
// serves a small JSON API on the loopback interface for the window.
package main

import (
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/MrKsey/y-node-desktop/core/internal/desktop"
)

// version is stamped by the build script.
var version = "dev"

func main() {
	apiPort := flag.Int("api-port", 7799, "loopback port of the control API")
	autoConnect := flag.Bool("connect", false, "connect as soon as the core starts")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}
	desktop.Version = version

	app, err := desktop.New()
	if err != nil {
		fmt.Fprintln(os.Stderr, "y-node-core:", err)
		os.Exit(1)
	}

	address := fmt.Sprintf("127.0.0.1:%d", *apiPort)
	listener, err := net.Listen("tcp", address)
	if err != nil {
		fmt.Fprintln(os.Stderr, "y-node-core: the control port is busy:", err)
		os.Exit(2)
	}
	server := &http.Server{
		Handler:           desktop.NewAPI(app).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	if *autoConnect || app.Config().AutoConnect {
		go func() {
			if err := app.Connect(); err != nil {
				fmt.Fprintln(os.Stderr, "y-node-core: connect:", err)
			}
		}()
	}

	// The window waits for this line before it starts polling the API.
	fmt.Printf("Y-NODE-CORE-READY %s\n", listener.Addr().String())
	_ = os.Stdout.Sync()

	go func() {
		if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
			fmt.Fprintln(os.Stderr, "y-node-core: api:", err)
		}
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)

	// The window keeps the stdin pipe open. When it closes the window (or
	// crashes), the pipe reaches EOF and the core shuts down in the same way as
	// on a signal, so the system proxy is never left pointing at a dead port.
	parentGone := make(chan struct{})
	go func() {
		var probe [1]byte
		for {
			if _, err := os.Stdin.Read(probe[:]); err != nil {
				close(parentGone)
				return
			}
		}
	}()

	select {
	case <-signals:
	case <-parentGone:
	}
	app.Shutdown()
	_ = server.Close()
}
