# Changelog

## 1.5.6

- **A second disconnect no longer leaves the client on the network.** Connect closed the stop channel of the previous session, and after a disconnect that channel was already closed: the second connect panicked inside the HTTP handler, the window showed "disconnected" while the node, the exit polling and the local proxy kept running, and the next connect answered "node is already running". Every session now owns a fresh stop channel, Disconnect clears it, and a stale node is released before a new one starts. The node is stopped before the status loop is awaited, so a stuck call cannot keep the client online.
- **Auto mode keeps IPv4.** A name that has an IPv4 address is never switched to IPv6: the AAAA query is asked only when the name has no A record. **Prefer** still puts IPv6 first; **Off** uses IPv4 only.
- **Faster and more reliable DNS.** The resolvers of one group are queried in parallel and the first usable answer wins, so one dead Yggdrasil resolver no longer delays every `.ygg` name by its timeout. Each group (exit, local, system) has its own three-second budget instead of one shared timeout.
- **The client reports its version on every connect.** The exit node keeps the device name and the app version from the last registration, so X-Node kept showing the version from the day the invite was redeemed. A registered client now registers once per session with an empty invite, which the server accepts for an allowlisted address.
- **"Add the best N" adds the rows from the top of the list.** A candidate added by the call was treated as infinitely slow because the live peer list did not know it yet, so every next row replaced it and the button ended with a peer from the bottom of the list.
- **Quieter proxy log.** A browser that closes a tab or cancels a download no longer writes "wsasend: An existing connection was forcibly closed" as a tunnel warning; the line is kept in the debug log.
- **Installers for every platform.** macOS releases now include a `.pkg` that installs into **Applications**, Linux releases include a `.deb` that installs into `/opt` with a menu entry, and the Windows installer restores the system proxy when it has to stop a running copy before an update.

## 1.5.5

- **A complete disconnect.** Disconnecting the tunnel now cancels the exit health check and any peer probe that is already running, closes the exit UDP association and releases the Yggdrasil node before the window says "disconnected". The core no longer keeps polling the exit or holding a Yggdrasil link after the button is pressed.
- **IPv6 follows the exit node.** With the IPv6 mode on **Auto**, a name is resolved to IPv4 first and to IPv6 only when the exit reports a working IPv6 path; **Prefer** puts IPv6 first and falls back to IPv4; **Off** uses IPv4 only.
- **Exit node card.** The card shows the "IPv6 off" state and explains why the client stopped sending IPv6 traffic.
- **Automatic update check.** **Settings → Update** now checks GitHub for a newer release on launch (optional) and on demand, and opens the release page.

## 1.0.0

- First public desktop build: Yggdrasil node, local HTTP and SOCKS5 proxy, system proxy switch, peers, DNS, exit nodes, services catalogue, logs and tray.
