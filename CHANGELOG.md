# Changelog

## 1.5.10

- **Find peers ranks the answers by access time, not by country.** The results were grouped by country: every server of the detected country came first, so a node in Vladivostok was shown above a faster one in Finland, and the replacement pool kept the same order. The country is only a prior now: the round still starts with the local servers, the list follows the measured latency alone, and a quarter of the discovery window is always kept for the closest foreign countries, so a large home country cannot hide a faster neighbour across the border.

## 1.5.9

- **The pinned exit peer and its resolver can be removed while the exit is off.** With the exit switch off, the pinned peer of the exit node shows a cross instead of the lock, and the cross takes the peer out of the active list; the resolver of the **DNS exit node** switch does the same in the tunnel DNS list. Switching the exit on brings the peer and the resolver back and the crosses turn into locks again. The **DNS exit node** switch keeps its position, so the choice is not lost.

## 1.5.8

- **A resource added by hand is never shown as built in.** The "built in" badge belongs to the catalogue, but it was decided by the entry id: editing a built-in entry into another address kept its `builtin:` id, and an older build could leave a `builtIn` flag in `config.json`, so `https://2ip.io` appeared with the badge. Editing the address of a built-in entry now turns it into a plain user resource and hides the original default; a configuration written by an older build is repaired on start, so an existing entry loses the badge after the update.
- **The idle client no longer spins the CPU or grows in memory.** The pulse animation on the tunnel card ran in a loop even while the tunnel was off, repainting the page sixty times a second, and every status tick rebuilt the whole window even when nothing had changed. The animation now runs only while the link is coming up or up and the page is on screen, and a status or list refresh that produced the same data no longer notifies the UI.
- **About shows the source code of this client.** The **Source code** line opens `https://github.com/MrKsey/y-node-desktop`.

## 1.5.7

- **The Results card is sorted by latency.** The list now shows the fastest answer first, in the same order "Add the best N" ranks it, so the peers the button keeps are the rows at the top of the card instead of one that was hidden below the fold.

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
