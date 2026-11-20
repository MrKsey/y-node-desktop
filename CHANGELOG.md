# Changelog

## 1.5.5

- **A complete disconnect.** Disconnecting the tunnel now cancels the exit health check and any peer probe that is already running, closes the exit UDP association and releases the Yggdrasil node before the window says "disconnected". The core no longer keeps polling the exit or holding a Yggdrasil link after the button is pressed.
- **IPv6 follows the exit node.** With the IPv6 mode on **Auto**, a name is resolved to IPv4 first and to IPv6 only when the exit reports a working IPv6 path; **Prefer** puts IPv6 first and falls back to IPv4; **Off** uses IPv4 only.
- **Exit node card.** The card shows the "IPv6 off" state and explains why the client stopped sending IPv6 traffic.
- **Automatic update check.** **Settings → Update** now checks GitHub for a newer release on launch (optional) and on demand, and opens the release page.

## 1.0.0

- First public desktop build: Yggdrasil node, local HTTP and SOCKS5 proxy, system proxy switch, peers, DNS, exit nodes, services catalogue, logs and tray.
