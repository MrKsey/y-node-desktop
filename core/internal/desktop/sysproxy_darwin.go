//go:build darwin

package desktop

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// macOS keeps the proxy per network service. The app applies the setting to
// every service that is currently enabled, which is what "Set proxy" in the
// network settings does for the active connection.

func listNetworkServices() []string {
	out, err := exec.Command("networksetup", "-listallnetworkservices").Output()
	if err != nil {
		return nil
	}
	var services []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "An asterisk") || strings.HasPrefix(line, "*") {
			continue
		}
		services = append(services, line)
	}
	return services
}

func setSystemProxy(enable bool, host string, port int) error {
	services := listNetworkServices()
	if len(services) == 0 {
		return fmt.Errorf("no network service was found")
	}
	var firstErr error
	for _, service := range services {
		state := "off"
		if enable {
			state = "on"
		}
		portText := strconv.Itoa(port)
		commands := [][]string{
			{"-setwebproxystate", service, state},
			{"-setsecurewebproxystate", service, state},
		}
		if enable {
			commands = append([][]string{
				{"-setwebproxy", service, host, portText},
				{"-setsecurewebproxy", service, host, portText},
				{"-setproxybypassdomains", service, "localhost", "127.0.0.1", "::1"},
			}, commands...)
		}
		for _, args := range commands {
			if out, err := exec.Command("networksetup", args...).CombinedOutput(); err != nil {
				if firstErr == nil {
					firstErr = fmt.Errorf("networksetup %s: %v (%s)", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
				}
				break
			}
		}
	}
	return firstErr
}

func systemProxyState() (bool, string) {
	services := listNetworkServices()
	if len(services) == 0 {
		return false, ""
	}
	out, err := exec.Command("networksetup", "-getwebproxy", services[0]).Output()
	if err != nil {
		return false, ""
	}
	text := string(out)
	if !strings.Contains(text, "Enabled: Yes") {
		return false, ""
	}
	host := ""
	port := ""
	for _, line := range strings.Split(text, "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		switch strings.TrimSpace(key) {
		case "Server":
			host = strings.TrimSpace(value)
		case "Port":
			port = strings.TrimSpace(value)
		}
	}
	if host == "" || port == "" {
		return false, ""
	}
	return true, host + ":" + port
}

// recoverSystemProxy clears a setting left behind by a core that was killed
// before it could shut down. Only an address that points at this app is
// touched.
func recoverSystemProxy(host string, port int) {
	enabled, address := systemProxyState()
	if !enabled || address != host+":"+strconv.Itoa(port) {
		return
	}
	_ = setSystemProxy(false, "", 0)
}
