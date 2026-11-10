# Toolkit Phase 1 polish + Phase 2 plan

_Builds on [`TOOLKIT_PLAN.md`](TOOLKIT_PLAN.md) and the audits in
[`NETUTILUS_PARITY.md`](NETUTILUS_PARITY.md)._

## Audit: what already exists in the main window

| Area | Existing implementation | Decision for the toolkit |
| --- | --- | --- |
| Interfaces / addresses / gateway / VPN | `InterfacesView` + `SystemInterfaceScanner`, bottom tab 2 | **Link**, do not embed a second copy. Open the main window on tab 2. |
| Diagnostics checks | `DiagnosticsView` + `NetworkDiagnosticsEngine`, bottom tab 6 | Toolkit Internet Check adds the verdict/path; both share `DiagnosticsViewModel`. Keep the main tab as the detail view and add a link to the toolkit verdict. |
| Speed test | Inline `throughputSection` in `DiagnosticsView` | Move the single Speed Test screen to the toolkit; replace the inline block with a link. Add history + schedule there. |
| Live Wi-Fi clients | `LiveClientDiscoveryView` from the network inspector (monitor capture) | Keep it as the frame-level tool; LAN Scanner uses ARP/Bonjour/TCP and links to it for per-client frames. |
| Vendor lookup | 58k-prefix `OUIParser` | Reuse directly for LAN Scanner; no second database. |
| Menu-bar alerts | `MenuBarExtra` + `MenuBarAlertEngine` (Wi-Fi events) | Add uptime status/events to the same menu-bar view; no second item. |
| OUI updates, sessions, stores | `OUIUpdater`, `...HistoryStore` patterns | Reuse the Application Support JSON-store pattern for uptime, LAN guard and speed history. |
| Raw network tools | `ToolCatalog` / `ToolConsoleView` (ping, traceroute, mtr, nmap, dig, iperf3…) | Remove the duplicated network entries from the catalogue; the toolkit is their home. Keep `wdutil`, `blueutil`, `airport`, AP/RF/SSH and custom commands. |

## Navigation

Sidebar order:

1. **Main screen** (opens the Wi-Fi analyzer window)
2. **Monitoring** — Uptime Monitor, LAN Scanner, Network Monitor (link), Wi-Fi Analyzer (link), Wi-Fi Networks (link)
3. **Diagnostics** — Internet Check, Ping, Traceroute, MTR, Speed Test
4. **DNS & Domains**
5. **Network Tools**

Links post `.lanfiSelectBottomTab` / open `main`, so the existing screen is reused.

## Phase 1 polish

### MTR

- `MTRService` repeats `SystemTracerouteRunner` N times, merges by TTL, and
  computes per-hop sent/received/loss/last/avg/best/worst/jitter.
- Streaming callback after each round; stop cancels between rounds.
- `MTRToolView` table + progress + copy.
- Tests with a scripted fake runner (loss, jitter, varying paths).

### Speed-test history and schedule

- `ThroughputReport` becomes `Codable`; `ThroughputMeasurement` adds an id and
  is stored by `ThroughputHistoryStore` (Application Support JSON, 50 entries).
- `SpeedTestSchedule` (off/hourly/6h/daily) persisted in UserDefaults; a
  `@MainActor` loop in `SpeedTestToolModel` checks every minute and runs when
  due, even if the toolkit window is closed (`ToolkitViewModel` lives in the app).
- History table with date, down/up/latency/grade; clear button.
- Tests for schedule due logic and store round-trip.

### Localisation

- Add the toolkit keys to `en`, `ru`, `de`, `fr`, `zh-Hans`
  `Localizable.strings`; dynamic values stay in `TechnicalLocalizer`.
- Verify no key is duplicated and each file parses.

## Phase 2

### Uptime Monitor

- `UptimeTarget` (HTTP/HTTPS URL or TCP host:port, interval, enabled),
  `UptimeCheckResult`, `UptimeStore` (targets + results, 7-day trim).
- `UptimeMonitor` schedules checks every 30 s, runs `URLSession`/`TCPProbe`,
  records uptime/latency/outages, and posts `UserNotifications` on up→down and
  down→up transitions.
- UI: target list, day/week/month history chart, uptime %, check-now, toggle.
- Menu bar: one status line for down targets; no second `MenuBarExtra`.

### LAN Scanner + Network Guard

- Local interface/subnet from `SystemInterfaceScanner`.
- ARP sweep (UDP nudge + `/usr/sbin/arp -an` parser), reverse DNS, OUI vendor,
  concurrent TCP probes for open ports/latency.
- `LANDevice` merge; `NetworkGuardStore` remembers known MACs and flags new
  devices with a notification; toggle per network.
- UI: table + inspector, filter, summary; link to `LiveClientDiscoveryView`
  for frame-level Wi-Fi clients.
- Tests: ARP parser, subnet enumeration, merge, guard diff.

### iperf3

- Locate Homebrew `iperf3`; run `-c host -p port -t seconds -J`, parse JSON
  intervals/summary; show down/up throughput and a chart; clear install hint
  when the binary is missing.
- Replaces the raw `ToolCatalog` entry and the "download iperf3" menu link.

## Order of work

1. Sidebar restructure + dedup links (this commit).
2. MTR + tests.
3. Speed history + schedule + tests.
4. Uptime Monitor + tests.
5. LAN Scanner + Guard + tests.
6. iperf3 + tests.
7. Localisation.
8. Release build, snapshots, docs.

Quality gates `crapper`/`dryer`/`mutator` are not installed in this repository;
they will be reported as not run rather than skipped silently.


## Delivered

- [x] Sidebar: Main screen first, Monitoring first, Network Monitor as a link,
      Diagnostics links to the toolkit, duplicate raw tools removed.
- [x] MTR service + table, 4 tests.
- [x] Speed history store, hourly/6h/daily schedule, history table, 4 tests.
- [x] Uptime Monitor models/store/checker/notifier, menu-bar status, 4 tests.
- [x] LAN Scanner ARP/ICMP/TCP fallback, Bonjour names, OUI vendors, Network
      Guard, 4 tests.
- [x] iperf3 JSON client + install hint, 4 tests.
- [x] Static toolkit strings localised in five languages (669 keys each, no
      duplicates).
- [ ] Whois, GeoIP, DNS Propagation and Visual Traceroute remain planned.
- [ ] The macOS Local Network permission is required for LAN MAC/vendor/TCP
      results; the app shows that hint when it is missing.
