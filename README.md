# Y-Node Desktop

A Yggdrasil client for Windows, macOS and Linux. The desktop app has no TUN
device and needs no administrator rights: it starts a Yggdrasil node, exposes a
local HTTP and SOCKS5 proxy, and can switch the system proxy to that port with
one click.

## How it works

```
┌──────────────────────────────┐        ┌──────────────────────────────┐
│ Flutter window               │  HTTP  │ y-node-core (Go)             │
│  Tunnel / Peers / Exit /     │ ─────▶ │  Yggdrasil node              │
│  Logs / Settings             │  JSON  │  HTTP proxy  127.0.0.1:7890  │
└──────────────────────────────┘        │  SOCKS5      127.0.0.1:7891  │
                                        │  system proxy (WinINET, ...) │
                                        └──────────────────────────────┘
```

The window is a thin client. The core owns the node, the proxy, the
configuration and the system proxy setting; the window only reads the state
once per second and sends commands. The core is a separate process
(`y-node-core.exe` on Windows, `y-node-core` elsewhere) that lives next to the
application binary, so the app can always find it.

There is no split tunnel: only the applications that use the proxy go through
Yggdrasil. That keeps the app free of drivers and elevation, and it is what the
system proxy switch is for.

### System proxy

| Platform | What is changed | Restored when |
| --- | --- | --- |
| Windows | `HKCU\...\Internet Settings` (`ProxyEnable`, `ProxyServer`, `ProxyOverride`) + `InternetSetOption` refresh | the switch is turned off, the tunnel stops, or the window closes |
| macOS | every enabled network service via `networksetup` | same |
| Linux | `org.gnome.system.proxy` via `gsettings` | same |

The previous Windows values are saved to `system-proxy-backup.json` in the
config directory before the first write, so turning the switch off returns the
user's own proxy (a corporate one, for example) instead of just clearing the
setting. If the core is killed hard, the next start notices that the system
proxy points at this app and clears it.

Firefox keeps its own proxy setting and is not touched; set it to
`127.0.0.1:7890` manually if you use it.

## Layout

```
core/                 Go: node, proxies, config, system proxy, JSON API
  cmd/y-node-core/    the process the window launches
  internal/yggnode/   the Yggdrasil bridge (shared with the Android app)
  internal/desktop/   App, Proxy, Config, API, per-OS system proxy
app/                  Flutter window (windows, macos, linux)
  lib/                api, core_process, app_state, models, ui/
scripts/              build scripts and the MSIX manifest
```

The core API listens on `127.0.0.1:7799`:

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/v1/health` | readiness probe |
| GET | `/v1/state` | counters, address, proxy ports, exit state |
| POST | `/v1/connect`, `/v1/disconnect` | start and stop the tunnel |
| POST | `/v1/system-proxy` | `{"enabled": true}` |
| GET/PUT | `/v1/config` | read and write the configuration |
| GET/POST/DELETE | `/v1/peers` | peer list |
| POST | `/v1/peers/auto` | download the public peer list and pick live nodes |
| POST | `/v1/peers/probe` | latency of the configured peers |
| GET/POST/DELETE | `/v1/exit` | exit profiles |
| POST | `/v1/exit/link` | add an X-Node `yggnode://exit` link |
| POST | `/v1/exit/check` | ask the exit node to resolve a name |
| GET | `/v1/logs` | the in-memory log |

## Building

The repository keeps the two halves independent, so the core can be rebuilt
without Flutter and the window without Go.

### Windows (x64, MSIX)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Version 1.0.0
```

Produces `dist\windows\` (the plain bundle) and
`dist\y-node-desktop-1.0.0-x64.msix`. The script builds the core, builds the
Flutter release, copies the core next to the window, packs the MSIX with
`makeappx.exe` from the Windows SDK and signs it with a self-signed certificate
that it creates on the first run (`dist\y-node-desktop-test.pfx`, password
`y-node-desktop`, and `dist\y-node-desktop-test.cer` for the trust step).

Installing the self-signed package needs administrator rights once:

```powershell
Import-Certificate -FilePath dist\y-node-desktop-test.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPeople
Add-AppxPackage -Path dist\y-node-desktop-1.0.0-x64.msix
```

`dist\windows\y_node_desktop.exe` runs without installation as well.

### macOS

```bash
./scripts/build-macos.sh 1.0.0
```

Needs Xcode command line tools and Flutter. The script builds the core for the
architecture of the machine, embeds it in `Contents/MacOS`, signs the bundle ad
hoc and writes `dist/macos/Y-Node.app`.

### Linux

```bash
./scripts/build-linux.sh 1.0.0
```

Needs the GTK 3 development headers (`libgtk-3-dev`), `ninja-build`, `cmake`,
`clang` and Flutter. Writes `dist/linux/y-node-desktop/` and a tarball next to
it.

### Cross-compiling only the core

```bash
cd core
GOOS=darwin GOARCH=arm64 go build -o bin/y-node-core-darwin-arm64 ./cmd/y-node-core
GOOS=linux  GOARCH=amd64 go build -o bin/y-node-core-linux-amd64  ./cmd/y-node-core
```

## Checks

```bash
cd core && gofmt -l . && go vet ./... && go test ./...
cd app  && flutter analyze && flutter test
```

## Exit nodes

The app speaks the same `yggnode://exit` links as the Android build and X-Node:
paste the link printed by the X-Node dashboard into **Exit node → Add link**.
While an exit node is enabled, the local proxy asks it to open public internet
connections and to resolve DNS, so no traffic leaves the Yggdrasil network in
the clear.

## Configuration

`config.json` lives in the per-user config directory:

* Windows: `%AppData%\Y-Node\config.json`
* macOS: `~/Library/Application Support/Y-Node/config.json`
* Linux: `~/.config/Y-Node/config.json`

The private key is stored there; changing it changes the Yggdrasil address.
