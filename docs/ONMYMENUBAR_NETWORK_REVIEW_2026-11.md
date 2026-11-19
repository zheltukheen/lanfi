# On My Menubar "Network" tag review — November 2026

Status: **input to [`GAP_ANALYSIS_2026-11.md`](GAP_ANALYSIS_2026-11.md)**.
Baseline: LanFi 5.4.0 (build 71). Source:
<https://onmymenubar.app/tags/network/>, read on 2026-11-18. The tag lists 22
apps; every listing's Overview and FAQ was read and compared with the shipped
code, not with the roadmap text.

The directory tag is a loose bucket. Ten of the 22 listings are not network
tools at all (a CI watcher, a commute timer, a remote downloader, two VPN
clients, a share automounter, a file-transfer app, a KDE Connect client, a
content blocker and an outbound firewall), so they are recorded as non-goals
rather than gaps. Twelve listings do something a network toolkit can do, and
they collapse into ten concrete gaps in the P3 section.

## The 22 listings

| Listing | What it actually does | LanFi today | Verdict |
| --- | --- | --- | --- |
| [Doorry](https://onmymenubar.app/doorry/) | Live TCP listening ports per process, localhost vs LAN binding, one-click kill, port-change notifications, global hotkey | Connections: read-only `lsof` sockets incl. `LISTEN`, grouped by app, SIGTERM on the owning process, local block rules | **Partial → P3.1**: TCP only, no exposure class, no change alerts, no hotkey |
| [AdGuard](https://onmymenubar.app/adguard/) | System-wide ad/tracker filtering with an HTTPS root certificate, per-app exclusions, statistics | None | **Out of scope** — content filtering; LanFi must not install a root certificate |
| [Octowatch](https://onmymenubar.app/octowatch/) | GitHub Actions CI status in the menu bar | None | **Not a network tool** |
| [TimeToGo](https://onmymenubar.app/timetogo/) | Commute travel time from Apple Maps traffic | None | **Not a network tool** |
| [Transloader](https://onmymenubar.app/transloader/) | Remote-initiated Mac downloads over iCloud | None | **Out of scope** — download manager |
| [Mojo Pulse](https://onmymenubar.app/mojo-pulse/) | Security posture (FileVault, Gatekeeper, firewall, SIP), unsigned processes, DNS hijack and ARP spoof checks, speed/latency, connection map, Bluetooth sonar | Speed test with bufferbloat, MTR per-hop latency, Connections, Security Watch (evil twin, downgrade, deauth), LAN Scanner | **Partial → P3.7**: no gateway-ARP or DNS-hijack check; posture audit stays out of scope |
| [Tunnelblick](https://onmymenubar.app/tunnelblick/) | OpenVPN client for `.ovpn` profiles | None | **Out of scope** — LanFi is not a VPN client |
| [WhyFi](https://onmymenubar.app/whyfi/) | Layered Wi-Fi/LAN/WAN metrics, 4 Hz radar, channel advice, DNS switching, captive-portal detection, AI-ready report, Cloudflare speed test with bufferbloat | Signal/noise/SNR/rate, channel advisor, diagnostics verdict with DNS timing and jitter, speed test with bufferbloat, HTML report | **Mostly matched → P3.3** (continuous captive-aware state), **P3.5** (resolver switching); the 4 Hz radar is an optional mode of P2.6 |
| [LanGuard](https://onmymenubar.app/languard/) | Disables Wi-Fi while Ethernet is active, physical-adapter filtering, wake-aware correction, master pause | Interface inventory only; no toggling | **Absent → P3.8** |
| [LuLu](https://onmymenubar.app/lulu/) | Outbound firewall: alert, allow/block, rules window, block-all, network monitor | Block rules that mark matching sockets and terminate the owning process; no packet filter | **Out of scope** for enforcement; the honest block-rule parity is already shipped |
| [TraceBar](https://onmymenubar.app/tracebar/) | Continuous traceroute, per-hop heatmap, menu-bar sparkline, adaptive probing, latency thresholds | Traceroute, MTR and Visual Traceroute, all on demand | **Partial → P3.2** |
| [Online Indicator](https://onmymenubar.app/online-indicator/) | Menu-bar real-internet state, custom icon sets, configurable probe URL and interval, IPv4/IPv6 copy | One-shot Internet Check, diagnostics dot in the menu bar, label styles, public IP | **Partial → P3.3**: no continuous state; arbitrary per-state icon sets are cosmetic and belong to D5 |
| [AutoMounter](https://onmymenubar.app/automounter/) | Auto-mounts SMB/WebDAV/AFP/NFS/FTP shares, discovery, Wake-on-LAN, post-mount scripts | Wake-on-LAN from the LAN Scanner; no mounting | **Out of scope** for mounting; WoL is matched |
| [Glinet Wireguard](https://onmymenubar.app/glinet-wireguard/) | Switches WireGuard peers on GL.iNet routers | None | **Out of scope** — router-specific VPN client |
| [VPN Peek](https://onmymenubar.app/vpn-peek/) | VPN status, DNS and IPv6 leak checks, public IP and geolocation, disconnect alerts | Public IP and country (GeoIP, menu bar), tunnel interfaces listed | **Absent → P3.4** |
| [DNS Easy Switcher](https://onmymenubar.app/dns-easy-switcher/) | DNS presets, provider speed test, cache flush, custom servers, admin/Touch ID authorization | DNS Lookup and Propagation with resolver choice; no benchmark, switching or flush | **Absent → P3.5** |
| [FireWally](https://onmymenubar.app/firewally/) | Per-app inbound/outbound counters, contacted domains, AI explanations, one-click block, hour/day history | Per-process received/sent rates (since previous sample), sockets, block rules, HTTP traffic capture | **Partial → P3.6**, **P3.10** |
| [SimplePing](https://onmymenubar.app/simpleping/) | Live ping latency in the menu bar, colour thresholds, configurable target and interval | Menu-bar latency metric (last diagnostics run) and the Ping tool | **Matched**; a continuous probe lands with P3.3 |
| [Shuttle](https://onmymenubar.app/shuttle/) | JSON-configured SSH host launcher that opens Terminal | Remote Sensors store SSH hosts but only run probes | **Partial → P3.9** |
| [Online Check](https://onmymenubar.app/online-check/) | HEAD probes with fallback host, drop notifications, Shortcuts conditions | Uptime Monitor (HTTP/TCP, notifications, menu-bar down count) and three App Intents | **Partial → P3.3** |
| [Soduto](https://onmymenubar.app/soduto/) | KDE Connect: clipboard, files, SMS, battery, find phone | None | **Out of scope** — device integration |
| [Blip](https://onmymenubar.app/blip/) | Peer-to-peer cross-platform file transfer | None | **Out of scope** — file transfer |

## Already matched, no new work

The tag confirms several surfaces shipped in 5.4.0 rather than exposing new
ones:

- **Connections console** (Doorry, LuLu, FireWally): sockets and listeners,
  grouping by app, SIGTERM, block rules, per-process rates.
- **Menu-bar meter** (SimplePing, Online Indicator, NetWorker Pro): throughput,
  signal, quality and latency metrics, sparkline, label styles, public IP.
- **Layered diagnostics** (WhyFi): one verdict that separates local link,
  router, provider, DNS and web, with DNS timing and ping jitter.
- **Speed test** (WhyFi): `networkQuality` throughput plus bufferbloat grade and
  per-SSID history.
- **Wake-on-LAN** (AutoMounter): magic packets from the LAN Scanner.
- **Security Watch** (Mojo Pulse): evil twin, security downgrade, randomized
  BSSID and captured deauth bursts.
- **Wi-Fi QR and known networks** (not in this tag, but the same menu-bar
  audience).

## New gaps

Each item is stated in full with acceptance criteria in
[`GAP_ANALYSIS_2026-11.md`](GAP_ANALYSIS_2026-11.md#p3--menu-bar-network-utilities-on-my-menubar-2026-11-18).

| # | Gap | Source listing | Why it matters |
| --- | --- | --- | --- |
| P3.1 | Listener watch: UDP sockets, localhost/LAN exposure class, new-listener and closed-port alerts, optional global hotkey | Doorry | Turns the Connections table from a snapshot into a watch; answers "is this service reachable from the LAN?" |
| P3.2 | Continuous route monitor: per-hop latency/loss heatmap over time, thresholds, adaptive probing, menu-bar route state | TraceBar | MTR is on demand; route flaps and evening congestion are only visible with history |
| P3.3 | Connectivity watchdog: continuous real-internet state, captive-portal verdict, configurable probe hosts and interval, drop notifications, Shortcut condition | Online Check, Online Indicator, WhyFi, SimplePing | The menu bar currently shows the last diagnostics run, not whether the internet works now |
| P3.4 | VPN status and leak checks: detect the active tunnel, DNS leak, IPv6 leak, drop alert | VPN Peek | Public IP exists; leak detection is the part users cannot do themselves |
| P3.5 | DNS resolver benchmark and opt-in switching: rank resolvers from this network, flush cache, custom servers, admin/Touch ID gate | DNS Easy Switcher, WhyFi | The toolkit measures DNS but cannot compare or change it |
| P3.6 | Per-app traffic history and domain attribution: hourly/daily bytes per app, top domains via capture and DNS, no payload | FireWally | "Since the previous sample" is not an answer to "what used the network today?" |
| P3.7 | LAN attack detection: gateway MAC/ARP change and DNS-hijack check feeding Security Watch | Mojo Pulse | Complements evil twin/deauth at the gateway and resolver layers |
| P3.8 | Wired/Wi-Fi link automation: Wi-Fi off while a physical Ethernet link is up, edge-triggered, wake-aware, pausable | LanGuard | A small, safe write action for dock users; requires explicit opt-in |
| P3.9 | SSH quick launch from saved sensors/hosts | Shuttle | Remote Sensors already store host, user, port and key; opening Terminal is the missing verb |
| P3.10 | Plain-language service descriptions for domains and processes: bundled catalogue first, on-device model when available | FireWally | Makes Connections readable without shipping data anywhere |

## Deliberate non-goals

| Capability | Listings | Reason |
| --- | --- | --- |
| Packet-filter enforcement, block-all firewall | LuLu, AdGuard | Needs a Network Extension or root helper. LanFi's block rules terminate the owning process and the UI says so; pretending to filter packets is worse than not filtering. |
| Content/ad blocking with a root certificate | AdGuard | A TLS-intercepting proxy is a different product with a much larger trust surface. |
| VPN client or VPN peer management | Tunnelblick, Glinet Wireguard | Protocol clients and vendor APIs are not analysis. |
| Network-share automount | AutoMounter | Mounting and credential handling turn a read-only analyzer into an actor. Wake-on-LAN is the useful, safe subset and is already shipped. |
| Cross-device file transfer, clipboard, SMS | Blip, Soduto | Device integration, not network diagnosis. |
| Remote-initiated downloads and CI/commute monitors | Transloader, Octowatch, TimeToGo | Not network tools; the tag is broader than the product. |
| System posture audit (FileVault, SIP, Gatekeeper) | Mojo Pulse | macOS and `fdesetup`/`csrutil` already report this; only the network-layer hijack checks are in P3.7. |

## What this adds to the plan

| Delta | Plan item | Cost |
| --- | --- | --- |
| Listener watch | P3.1 | S |
| Continuous route monitor | P3.2 | M |
| Connectivity watchdog | P3.3 | S/M |
| VPN leak checks | P3.4 | M |
| DNS benchmark and switching | P3.5 | S/M |
| Per-app traffic history and domains | P3.6 | M |
| ARP/DNS hijack detection | P3.7 | M |
| Wired/Wi-Fi automation | P3.8 | S |
| SSH quick launch | P3.9 | S |
| Plain-language service descriptions | P3.10 | S/M |

Nothing here changes the P0/P1/P2 order: P0.1 signing and P0.4 performance still
come first. P3.3 is the cheapest visible win because the menu bar is already the
product's permanent surface.

## Sources

- <https://onmymenubar.app/tags/network/> (index, read 2026-11-18)
- One listing per app: <https://onmymenubar.app/doorry/>,
  <https://onmymenubar.app/adguard/>, <https://onmymenubar.app/octowatch/>,
  <https://onmymenubar.app/timetogo/>, <https://onmymenubar.app/transloader/>,
  <https://onmymenubar.app/mojo-pulse/>, <https://onmymenubar.app/tunnelblick/>,
  <https://onmymenubar.app/whyfi/>, <https://onmymenubar.app/languard/>,
  <https://onmymenubar.app/lulu/>, <https://onmymenubar.app/tracebar/>,
  <https://onmymenubar.app/online-indicator/>,
  <https://onmymenubar.app/automounter/>,
  <https://onmymenubar.app/glinet-wireguard/>,
  <https://onmymenubar.app/vpn-peek/>,
  <https://onmymenubar.app/dns-easy-switcher/>,
  <https://onmymenubar.app/firewally/>,
  <https://onmymenubar.app/simpleping/>, <https://onmymenubar.app/shuttle/>,
  <https://onmymenubar.app/online-check/>, <https://onmymenubar.app/soduto/>,
  <https://onmymenubar.app/blip/>
