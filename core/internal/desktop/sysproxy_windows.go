//go:build windows

package desktop

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"golang.org/x/sys/windows/registry"
)

// The desktop app is a plain user process: the system proxy is the per-user
// WinINET setting, the same one the Windows settings app writes. Browsers that
// follow the system proxy (Edge, Chrome, Internet Explorer) pick it up at once
// after the refresh call; Firefox keeps its own setting and is left alone.
//
// The previous values are saved before the first write, so turning the switch
// off restores whatever the user had (a corporate proxy, for example) instead
// of just clearing the setting.

const internetSettingsKey = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`

var (
	wininetDLL        = syscall.NewLazyDLL("wininet.dll")
	internetSetOption = wininetDLL.NewProc("InternetSetOptionW")
)

const (
	internetOptionRefresh         = 37
	internetOptionSettingsChanged = 39
)

func notifyWinINET() {
	_, _, _ = internetSetOption.Call(0, internetOptionSettingsChanged, 0, 0)
	_, _, _ = internetSetOption.Call(0, internetOptionRefresh, 0, 0)
}

// proxyBackup is the state of the Internet Settings key before the app touched
// it.
type proxyBackup struct {
	Enable      int    `json:"enable"`
	Server      string `json:"server"`
	Override    string `json:"override"`
	HasServer   bool   `json:"hasServer"`
	HasOverride bool   `json:"hasOverride"`
}

func proxyBackupPath() (string, error) {
	dir, err := ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "system-proxy-backup.json"), nil
}

func readProxyBackup() (proxyBackup, bool) {
	path, err := proxyBackupPath()
	if err != nil {
		return proxyBackup{}, false
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return proxyBackup{}, false
	}
	var backup proxyBackup
	if err := json.Unmarshal(raw, &backup); err != nil {
		return proxyBackup{}, false
	}
	return backup, true
}

func writeProxyBackup(backup proxyBackup) {
	path, err := proxyBackupPath()
	if err != nil {
		return
	}
	raw, err := json.MarshalIndent(backup, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(path, raw, 0o600)
}

func clearProxyBackup() {
	if path, err := proxyBackupPath(); err == nil {
		_ = os.Remove(path)
	}
}

func setSystemProxy(enable bool, host string, port int) error {
	key, _, err := registry.CreateKey(registry.CURRENT_USER, internetSettingsKey, registry.SET_VALUE|registry.QUERY_VALUE)
	if err != nil {
		return fmt.Errorf("open the Internet Settings key: %w", err)
	}
	defer key.Close()

	if !enable {
		if backup, ok := readProxyBackup(); ok {
			if err := restoreProxy(key, backup); err != nil {
				return err
			}
			clearProxyBackup()
			notifyWinINET()
			return nil
		}
		if err := key.SetDWordValue("ProxyEnable", 0); err != nil {
			return err
		}
		notifyWinINET()
		return nil
	}

	if _, ok := readProxyBackup(); !ok {
		backup := proxyBackup{}
		if value, _, err := key.GetIntegerValue("ProxyEnable"); err == nil {
			backup.Enable = int(value)
		}
		if value, _, err := key.GetStringValue("ProxyServer"); err == nil {
			backup.Server, backup.HasServer = value, true
		}
		if value, _, err := key.GetStringValue("ProxyOverride"); err == nil {
			backup.Override, backup.HasOverride = value, true
		}
		writeProxyBackup(backup)
	}

	address := host + ":" + strconv.Itoa(port)
	if err := key.SetStringValue("ProxyServer", address); err != nil {
		return err
	}
	// Local names and the loopback stay direct: the proxy would only add a hop
	// for them, and a local service must keep working while the node is up.
	if err := key.SetStringValue("ProxyOverride", "localhost;127.*;[::1];<local>"); err != nil {
		return err
	}
	if err := key.SetDWordValue("ProxyEnable", 1); err != nil {
		return err
	}
	notifyWinINET()
	return nil
}

func restoreProxy(key registry.Key, backup proxyBackup) error {
	if backup.HasServer {
		if err := key.SetStringValue("ProxyServer", backup.Server); err != nil {
			return err
		}
	} else if err := key.DeleteValue("ProxyServer"); err != nil && !errors.Is(err, registry.ErrNotExist) {
		return err
	}
	if backup.HasOverride {
		if err := key.SetStringValue("ProxyOverride", backup.Override); err != nil {
			return err
		}
	} else if err := key.DeleteValue("ProxyOverride"); err != nil && !errors.Is(err, registry.ErrNotExist) {
		return err
	}
	return key.SetDWordValue("ProxyEnable", uint32(backup.Enable))
}

func systemProxyState() (bool, string) {
	key, err := registry.OpenKey(registry.CURRENT_USER, internetSettingsKey, registry.QUERY_VALUE)
	if err != nil {
		return false, ""
	}
	defer key.Close()
	enabled, _, err := key.GetIntegerValue("ProxyEnable")
	if err != nil || enabled == 0 {
		return false, ""
	}
	server, _, err := key.GetStringValue("ProxyServer")
	if err != nil {
		return false, ""
	}
	return true, server
}

// recoverSystemProxy clears a setting left behind by a core that was killed
// before it could shut down. Only an address that points at this app is
// touched; a proxy of the user is never rewritten. A core that is still
// listening on that port owns the setting, so a second instance starting next
// to it leaves the running tunnel alone.
func recoverSystemProxy(host string, port int) {
	enabled, server := systemProxyState()
	if !enabled {
		clearProxyBackup()
		return
	}
	if server != host+":"+strconv.Itoa(port) {
		return
	}
	if proxyPortAlive(host, port) {
		return
	}
	_ = setSystemProxy(false, "", 0)
}

// proxyPortAlive reports whether something already accepts connections on the
// address the system proxy points at.
func proxyPortAlive(host string, port int) bool {
	address := net.JoinHostPort(host, strconv.Itoa(port))
	conn, err := net.DialTimeout("tcp", address, 500*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}
