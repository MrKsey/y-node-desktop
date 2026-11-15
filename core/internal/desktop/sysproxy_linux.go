//go:build linux

package desktop

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// Linux has no single system proxy. The app writes the GNOME/GTK setting, which
// is what most desktops and browsers read; a session that does not run gsettings
// keeps working with the proxy address shown in the window.

func gsettings(args ...string) (string, error) {
	out, err := exec.Command("gsettings", args...).CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("gsettings %s: %v (%s)", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

func setSystemProxy(enable bool, host string, port int) error {
	if !enable {
		_, err := gsettings("set", "org.gnome.system.proxy", "mode", "none")
		return err
	}
	portText := strconv.Itoa(port)
	steps := [][]string{
		{"set", "org.gnome.system.proxy", "mode", "manual"},
		{"set", "org.gnome.system.proxy.http", "host", host},
		{"set", "org.gnome.system.proxy.http", "port", portText},
		{"set", "org.gnome.system.proxy.https", "host", host},
		{"set", "org.gnome.system.proxy.https", "port", portText},
		{"set", "org.gnome.system.proxy", "ignore-hosts", "['localhost', '127.0.0.0/8', '::1']"},
	}
	for _, args := range steps {
		if _, err := gsettings(args...); err != nil {
			return err
		}
	}
	return nil
}

func systemProxyState() (bool, string) {
	out, err := gsettings("get", "org.gnome.system.proxy", "mode")
	if err != nil {
		return false, ""
	}
	if !strings.Contains(out, "manual") {
		return false, ""
	}
	hostOut, err := gsettings("get", "org.gnome.system.proxy.http", "host")
	if err != nil {
		return false, ""
	}
	portOut, err := gsettings("get", "org.gnome.system.proxy.http", "port")
	if err != nil {
		return false, ""
	}
	host := strings.Trim(strings.TrimSpace(hostOut), "'")
	port := strings.TrimSpace(portOut)
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
