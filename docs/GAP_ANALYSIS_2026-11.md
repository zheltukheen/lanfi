# Gap analysis — November 2026

Status: **active plan**. Baseline: LanFi 5.4.0 (build 71).
Scope: post-Netutilus parity, compared with WiFi Explorer Pro 3.10, NetSpot 6,
Airtool 2, the public macOS Wi-Fi APIs, the menu-bar/utility segment covered in
[`REFERENCE_APPS_REVIEW_2026-11.md`](REFERENCE_APPS_REVIEW_2026-11.md)
(NetWorker Pro, AirRadar 8, PeakHour 6 and an Unstore buyer's guide), and the
22 listings on the On My Menubar network tag reviewed in
[`ONMYMENUBAR_NETWORK_REVIEW_2026-11.md`](ONMYMENUBAR_NETWORK_REVIEW_2026-11.md).

This document intentionally goes beyond
[`COMMERCIAL_GAP.md`](COMMERCIAL_GAP.md) and
[`NETUTILUS_PARITY.md`](NETUTILUS_PARITY.md): those tracks are shipped. The
remaining work is **trust, continuity, professional depth, presentation and
engineering speed**. Presentation is tracked explicitly as the D-series below,
because the delivered analysis depth is currently invisible in a screenshot.

## Baseline

| Metric | Value |
| --- | ---: |
| Swift files (Models/Services/ViewModels/Views/Utils/CLI) | ~214 |
| Lines in those folders | ~42,000 |
| Test methods | 385 app + 6 core |
| Settings tabs | 11 |
| SwiftPM modules | 1 (`LanFiCore`: settings, target parsing, probe models) |
| Distinct preference keys (one `AppSettingsKey` catalogue) | 73 |
| Key literals outside the catalogue / error domains | 0 / 13 |
| App targets | 1 app + CLI + tests |
| Third-party runtime dependencies | Sparkle only |

## Priority summary

| # | Item | Area | Impact | Effort |
| --- | --- | --- | --- | --- |
| P0.1 | Developer ID, notarization and TCC self-check | Trust / data access | Critical | M |
| P0.2 | Passive/directed scan and 6 GHz SP visibility | Analyzer | High | M |
| P0.3 | Persistent Wi-Fi Monitor with events and alerts | New tool | High | M |
| P0.4 | OUI/analyzer/history/table performance hot spots | Speed | High | S/M |
| P0.5 | Group by physical AP, history statistics | Analyzer depth | Medium | S/M |
| P0.6 | Menu-bar live meter: throughput, mini graph, latency | New surface | High | S/M |
| P1.1 | Security Watch: rogue AP, evil twin, live deauth | New tool | High | M |
| P1.2 | Roaming and band-steering test | New tool | High | M |
| P1.3 | Client analytics from captures | New tool | Medium | M/L |
| P1.4 | Survey Planning 2.0 and active survey | Survey | High | L |
| P1.5 | Combined report / case file | Workflow | Medium | S/M |
| P1.6 | Shortcuts, App Intents, widgets, MCP actions | Integrations | Medium | M |
| P1.7 | Known networks inventory and Wi-Fi QR | Workflow | Low | S |
| P1.8 | Open connections and per-process traffic | New tool | Medium | M |
| P1.9 | GPS scan map and saved collections | New tool | Medium | M |
| P1.10 | All-band RF overview with overlap | Presentation | High | S/M |
| P2.1 | Spectrum hub: Wi-Spy live, remote WLAN Pi, NetAlly | Hardware | High | L |
| P2.2 | BLE/Zigbee interference sources | Hardware | Low | M |
| P2.3 | Sandboxed MAS build split | Distribution | Medium | L |
| P2.4 | 802.11-2024/802.11bn decoder readiness | Future | Low | S |
| P2.6 | Connected-link telemetry: rate, MCS/NSS, PHY, noise chart | Analyzer depth | Medium | S |
| P3.1 | Listener watch: UDP, exposure class, port-change alerts | Security / workflow | Medium | S |
| P3.2 | Continuous route monitor with per-hop heatmap | New surface | Medium | M |
| P3.3 | Connectivity watchdog: online state, captive portal, Shortcut | Menu bar | High | S/M |
| P3.4 | VPN status and DNS/IPv6 leak checks | Security | Medium | M |
| P3.5 | DNS resolver benchmark and opt-in switching | Toolkit | Medium | S/M |
| P3.6 | Per-app traffic history and domain attribution | Monitoring | Medium | M |
| P3.7 | Gateway ARP and DNS-hijack detection | Security | High | M |
| P3.8 | Wired/Wi-Fi link automation | Automation | Low | S |
| P3.9 | SSH quick launch from saved sensors | Workflow | Low | S |
| P3.10 | Plain-language service descriptions | Presentation | Low | S/M |
| P4.1 | Privileged helper with a hash-pinned binary | Engineering | Medium | M/L |
| P4.2 | Supervised worker lifecycle: readiness, retry, auto-restart | Engineering | High | S/M |
| P4.3 | DNS console: record types, DoH/DoT/DoQ, compare mode | Toolkit | High | S/M |
| P4.4 | NAT type and STUN reachability test | Toolkit | Medium | M |
| P4.5 | Command palette over tools and settings | Workflow | High | S/M |
| D1 | Design tokens and shared components | Presentation | High | M |
| D2 | Hero RF overview, first run and empty states | Presentation | High | S/M |
| D3 | Table presentation: density, bars, relative time, wording | Presentation | High | S/M |
| D4 | Chart and inspector visual language | Presentation | Medium | M |
| D5 | Menu-bar and window chrome polish | Presentation | Medium | S |
| D6 | Settings, Help and onboarding restyle | Presentation | Medium | M |
| D7 | Accessibility visual pass | Presentation | Medium | S/M |
| D8 | Release visual assets: screenshots, icon, site | Presentation | Medium | S |

---

## P0.1 — Signing, notarization and TCC

Ad-hoc signing is not only a Gatekeeper problem. SSID/BSSID live behind
Location Services (TCC), and Apple DTS states that TCC needs a stable
code-signing identity: not unsigned, not ad-hoc. macOS 14.4 removed the
`airport` CLI and `wdutil` redacts BSSIDs; macOS 26/27 reports show SSID
redaction when Location Services is unavailable.

Current state: `build.sh` signs with `codesign --sign -` by default and
`project.yml` sets `CODE_SIGN_IDENTITY: "-"`.

Tasks:

- [ ] Apple Developer Program, Developer ID Application certificate.
- [ ] Sign nested Sparkle/XPC code individually; hardened runtime; timestamp.
- [ ] `notarytool submit --wait`, staple DMG and ZIP.
- [x] Add a launch-time self-check: if scan results have empty SSID/BSSID while
      Wi-Fi is on, show a diagnostic instead of an empty table. Implemented in
      `ScanHealth.identifiersHidden` + `ScanHealthBanner`.
- [x] Document the permission reset risk after updates in `DISTRIBUTION.md`,
      including the recovery steps and the signed-build expectation.

Acceptance: a clean Mac downloads the DMG, launches without a Gatekeeper
workaround, grants Location Services once, and keeps SSID/BSSID after an
update.

## P0.2 — Passive and directed scan

`WiFiScanner` only performs an active `scanForNetworks`. WiFi Explorer Pro 3
ships active, passive and directed modes. macOS filters standard-power 6 GHz
APs from active scans; passive scanning is the documented workaround. It also
finds beacon-only and hidden networks and gives a more honest channel load.

Hardware caveat: on Apple N1 (M5 Pro/Max, M5 Air, A18 Pro) rapid channel
switching is unreliable for third-party apps; both WiFi Explorer and Airtool
document this. The feature needs a capability matrix and a clear fallback.

Tasks:

- [x] Scan mode model (`active`, `passive`, `directed`) with a capability probe
      (`Models/ScanModePlan.swift`, `Services/ScanHardwareProbe.swift`).
- [x] Passive engine over the monitor interface, channel list and dwell time
      (`Services/PassiveScanEngine.swift`).
- [x] 6 GHz PSC/RNR-aware channel list; SP/LPI labelling where available.
- [x] UI: mode picker, unsupported-hardware explanation, progress
      (`Views/WiFiWorkspace/PassiveScanSheet.swift`).
- [x] Tests for channel planning (`Tests/ScanModePlanTests.swift`); opt-in
      hardware smoke test (`LANFI_HARDWARE_SMOKE=1`).

Acceptance: on supported Macs, passive mode discovers a 6 GHz SP AP that the
active scan omits; on N1 Macs the UI explains why it is unavailable instead of
failing silently.

## P0.3 — Persistent Wi-Fi Monitor

Today history is 180 seconds in memory; alerts are limited to weak signal, open
network and channel change. WiFi Explorer Pro 3 has a History inspector;
NetSpot has snapshots and zones.

Tasks:

- [x] Persistent store: connected-link raw samples plus per-BSSID aggregates
      for every visible network (JSON snapshot today; SQLite/JSONL if volume
      grows).
- [x] Retention settings: 1 h / 24 h / 7 d / 30 d.
- [x] Connected-link statistics (min/avg/max/p95) and peer aggregates
      (min/max/avg, sample count, last seen).
- [x] Event log: connected, disconnected, roamed, channel change, security
      downgrade, PMF loss, WPS enabled and weak-signal crossing.
- [x] Deauth-burst events from capture security reports, with an alert toggle
      and foreground notification.
- [x] Roaming-failure events when a roam lands on a much weaker link
      (≤ −80 dBm or >10 dB worse); a full Roaming Test is still open.
- [x] Notification rules with quiet hours and per-kind cooldown.
- [x] Before/after comparison for the last 1 h / 6 h / 24 h.
- [x] Timeline view, peer list and CSV exports (connected samples, visible
      networks).
- [x] Tests for events, retention, peers, comparison and store round-trip.

Acceptance: leave LanFi running for 24 hours, open the monitor, see a stable
timeline and at least one correctly deduplicated event per real change.

## P0.4 — Performance hot spots

- [x] `OUIParser.vendor` decodes custom overrides for every BSSID; cache and
      invalidate on write.
- [x] Preload the 1.7 MB OUI database on a background task at launch.
- [x] Pack the OUI database into an integer-key index; lookup no longer allocates
      four prefix strings per BSSID.
- [ ] Move the index to a persisted binary file if startup parsing becomes a
      bottleneck.
- [x] `NetworkAnalyzer.analyze` filters the whole network list per network and
      looks up findings with `first(where:)`; group by band once and index by
      id.
- [x] Four `@Published` history dictionaries are written once per network per
      scan; batch them into one published update per scan.
- [x] `WiFiTableView` keeps its structure cache and reloads only the visible
      rows when row/column identity is unchanged; filters, sorts and column
      changes still trigger a full reload.
- [x] Survey heatmap moved off-main: the grid is built from an immutable
      `SurveyHeatmapRequest` in a detached task and the fingerprint now includes
      RSSI and wall/AP geometry.
- [x] Fast/Balanced/High heatmap detail setting (8/6/4 pt cells).
- [x] Progressive heatmap tiles: the grid is streamed in 16-row chunks, so the
      first rows paint before the full plan finishes.
- [x] Captures are memory-mapped (`mappedIfSafe`) instead of copied into
      resident memory before parsing.
- [x] `PcapPacketIndex` indexes offsets/lengths/link type/timestamp without
      copying packet bytes; `summary` slices packets on demand for beacons,
      clients and security.
- [x] CSV/JSON encoding moved into pure `ScanCSVExporter` and
      `ScanJSONExporter` values; the save panel then encodes and writes both on
      a background task.
- [x] Adaptive scan interval: 15 s in the background, 30 s in Low Power Mode,
      base interval when active, with a settings toggle and pure `ScanCadence`
      tests.

Acceptance: a 300-network scan applies filters and updates the table without a
visible hitch; the OUI warm path does no JSON decoding; a 500 MB–1 GB pcap
opens without a multi-gigabyte memory spike.

## P0.5 — Analyzer depth

- [x] Group by advertised AP name across 2.4/5/6 GHz; unnamed radios stay as
      separate BSSID groups.
- [x] Infer co-located radios for APs that do not advertise a name
      (`CoLocatedAPDetector`); the inspector's "Same access point (inferred)"
      section lists the sibling radios with band, channel, signal and BSSID and
      jumps to them.
- [x] History statistics (min/avg/max/p95) in the inspector.
- [x] SSID overhead as a percentage of airtime (beacon airtime already exists),
      shown in the inspector's technical specs as well as the column.
- [~] Decoder to 802.11-2024/WPA3 v3.5: Extended BSS Load (193), Multiple
      BSSID/non-transmitted profiles (71), 320 MHz, MLO and RSNE are decoded.
      RSNE Override / RSNE Override 2 (OUI 50-6F-9A, types 0x29/0x2A) are decoded
      with the same RSNE parser, so a Wi-Fi 7 compatibility-mode AP shows its
      SAE/AKM-24 overrides (raw-IE view plus an "RSN override" fact in the
      security block); the same vendor OUI names Hotspot 2.0 (0x10) and SAE-PK
      (0x1F). The WFA Capabilities element body (capability bitmap) and RSNXE
      Override (0x2B) remain open.
- [x] 6 GHz PSC hints and a “why is this AP not visible” explanation
      (`VisibilityAdvisor`): PSC vs non-PSC channels, DFS sharing and hidden
      SSIDs, plus the same hint in the empty workspace.
- [x] SP/LPI power-mode labels: CoreWLAN does not expose the 6 GHz power mode,
      so the HE Operation element's 6 GHz Operation Information is decoded
      instead (`SixGHzOperationInfo`); the inspector's Regulatory section shows
      LPI / SP / VLP, and the raw IE view gains the same lines. Regulatory info
      is domain-dependent, so the labels follow the US/FCC meaning.
- [x] RNR (Reduced Neighbor Report) decoding into neighbouring-channel hints;
      `ReducedNeighborReport` decodes operating class, channel, BSSID, short
      SSID, BSS parameters, 20 MHz PSD and MLD parameters, and the IE view lists
      each neighbour with its band. Decoder-only, as planned.
- [ ] Wi-Fi 8/802.11bn decoder versioning. Draft 2.0 entered working-group
      ballot in August 2026; certification is expected in 2028, so this is
      future-proofing, not a current blocker.

## P0.6 — Menu-bar live meter

The `MenuBarExtra` today is a status list: alerts, connected network, one
quality number, a diagnostics dot and an uptime line. NetWorker Pro and PeakHour
both make the menu bar the primary surface, and it is the cheapest way to stay
in front of the user without a window.

Tasks:

- [x] Throughput sampler over `getifaddrs` (`ifi_ibytes`/`ifi_obytes` deltas,
      primary interface and Wi-Fi interface separately), smoothed over 2–5 s.
- [x] `Canvas` sparkline of the last 60 samples for the menu-bar label, in the
      PeakHour style: compact, no axes, current value as text.
- [x] Menu-bar label configuration: icon only, icon + number, icon + graph;
      metric choice (throughput / signal / quality / latency); unit choice
      (bit/s, byte/s) persisted through `AppSettings`.
- [x] Expand the popover: throughput block with sparkline, connected-link block
      (rate, band, channel, width), latency strip from the diagnostics engine,
      public IP with country (reuse `GeoIP`), existing alerts and uptime rows.
- [x] Keep a single `MenuBarExtra` (see `TOOLKIT_PHASE2_PLAN.md`); no second
      status item.
- [x] Pure `ThroughputSampler` / `TokenBucket` values with tests; the sampler
      runs every 2 s while the app is active and every 30 s while it is in the
      background.

Acceptance: with the menu bar visible, the label shows a live sparkline that
reacts to a large download within one sample interval, the popover shows the
same numbers, and the sampler costs no measurable battery on an idle Mac.

## P1 — New tools

- [x] **Security Watch** — rogue AP/evil twin, security downgrade and
      randomized BSSIDs from the live scan, plus captured deauth bursts; no
      framing, injection or deauth, as designed.
- [~] **Roaming Test** — BSSID transitions, 802.11k/v/r capability detection,
      sticky client and band-steering verdicts ship; reconnect time and packet
      loss per roam remain open.
- [~] **Client Analytics** — advertised per-AP client load, utilization and
      insights from beacons plus captured client observations ship; per-client
      airtime and retries need a capture-based accounting pass.
- [~] **Survey Planning 2.0** — free-space planner, grid layout, coverage
      estimate, blank metre-grid plans and the active-survey advisor ship.
      Antenna patterns, material-aware loss (the fixed 12 dB per-floor term is
      still in place), cutouts and calibration against samples remain open.
- [~] **Active Survey** — required samples, covered cells, gaps and the next
      target ship; throughput/latency per point, auto-walk and the multi-floor
      diff remain open.
- [~] **Combined report** — the self-contained HTML report with scan, survey,
      diagnostics and speed-test sections ships from the Data menu; PDF,
      branding and scheduled delivery remain open.
- [~] **Shortcuts/App Intents/widgets** — scan, connected network and speed
      test intents with Shortcut phrases ship; export, capture and widgets
      remain open.
- [ ] **MCP 2.0** — live actions (`scan now`, `start capture`, `survey sample`),
      not only the read-only snapshot.
- [x] **Known Networks / Wi-Fi QR** — saved-network inventory with security,
      live presence and a guest QR. Read-only: LanFi never edits or reads saved
      Wi-Fi passwords.
- [x] **Connections** — open TCP connections with process, PID, user, endpoints
      and state, grouped by process, from read-only `lsof` (never elevated;
      terminating the owning process is a separate explicit action, and no
      socket is closed from outside).
- [x] **Per-process traffic** — per-PID received/sent deltas over a rolling
      window with the app's own traffic excluded and a privacy note in the
      screen; parsed locally, nothing leaves the machine.
- [x] **Traffic accounting** — day / week / month / total volumes per interface
      from the same sampler, stored locally in
      `traffic-accounting.json`, with a reset control and CSV export
      (`TrafficLedger`, `TrafficAccounting`, Data usage card in Network
      Monitor).
- [ ] **GPS scan map** — pin scanned networks on MapKit, colour open networks
      green and secured ones red, keep the best-signal position per BSSID, and
      save each trip as a named collection that can be reopened or exported
      (GeoJSON + CSV). Requires `NSLocationWhenInUseUsageDescription` rationale
      in `PRIVACY.md`; opt-in per trip, never automatic.
- [x] **RF overview** — one screen that draws 2.4, 5 and 6 GHz side by side with
      every AP's span, overlap shading and the recommended channel marked (see
      D2 for the visual treatment). This is the screenshot the Unstore guide
      says buyers look for. Shipped 2026-11-16 as bottom tab 9 "All Bands".

Not planned from the same sources: auto-join of the best network, writing
network passwords to the Keychain, and spoken SSIDs. They turn a read-only
analyzer into an actor with credentials and add a failure surface that the
product does not need.

## P2 — Hardware and platform

- [ ] Spectrum hub: live Wi-Spy, remote WLAN Pi spectrum, NetAlly NXT-2000,
      and interferer classification.
- [ ] BLE iBeacon/Eddystone scanner; Zigbee adapter support.
- [ ] Privileged helper for capture (`SMAppService`) instead of an admin
      password per capture; multi-channel/dwell capture plan; orchestration of
      multiple remote sensors.
- [ ] Live deauth/disassoc/EAPOL counters during a capture, not only after the
      file is analyzed.
- [ ] Split a sandboxed Mac App Store build from the Developer ID build rather
      than trying to make one binary do both.
- [ ] Native probe layer for diagnostics (today `DiagnosticsEngine` shells out
      to `/sbin/ping`; macOS 26 child processes can lose Local Network access).
- [x] Speed test: keep `networkQuality` as the transport; the bufferbloat grade
      and the per-network history over time (grouped by SSID, with deltas and
      averages) are delivered.
- [ ] Connected-link telemetry: poll `CWWiFiClient().interface()` for
      `transmitRate()`, `noise()`, `ssid()`, `bssid()` and the negotiated PHY on
      a slow timer (5 s) and keep it in the Monitor store next to RSSI, so the
      Link inspector can show rate, PHY, width, streams and MCS/NSS over time.
      CoreWLAN does not expose MCS or NSS for the live link; derive NSS from the
      HT/VHT/HE capability IEs of the connected BSSID and label the value as
      capability, not measurement. An optional 4 Hz live mode for physical
      placement (WhyFi Radar) can ride the same sampler later, but only after
      the 5 s store is in place.
- [x] Noise in the history chart: `SignalHistoryView` plots RSSI only. Add the
      AirRadar-style mode switch (signal / noise / both) using the noise value
      already carried by `NetworkModel`. (Verified present: the "History mode"
      picker drives `HistoryChartMode`, and percent mode falls back to signal.)
- [x] Wi-Fi card selection: `WiFiScanner` accepts a preferred interface name and
      Settings → Wi-Fi picks it; the workspace toolbar now shows a "Scanning
      with <interface>" label next to the scan controls (system default included).
- [ ] SNMP/UPnP polling for router/NAS targets (PeakHour pattern): read-only
      v2c GET of standard interface counters plus SSDP discovery, with a strict
      timeout and no credential storage. Later bucket; only if the menu-bar
      meter proves useful.

## P3 — Menu-bar network utilities (On My Menubar, 2026-11-18)

Source: [`ONMYMENUBAR_NETWORK_REVIEW_2026-11.md`](ONMYMENUBAR_NETWORK_REVIEW_2026-11.md).
The tag has 22 listings; twelve are relevant and ten are non-goals recorded at
the bottom of this document. These items extend the shipped Connections console
(P1.8) and menu-bar meter (P0.6); they do not reopen them.

### P3.1 — Listener watch

Doorry watches listening sockets, separates loopback from LAN-reachable
services, kills the owner and notifies when the set changes. Connections is a
manual snapshot over `lsof -nP -iTCP`, so UDP servers, exposure and change
events are missing.

Tasks:

- [x] Add UDP listeners (`-iUDP` in the same read-only `lsof` call) to the same
      table behind an "Include UDP listeners" toggle, with the transport in the
      Proto column; the TCP pass stays the fast default. UDP sockets count as
      listeners, because they answer clients without a `LISTEN` state.
- [x] Classify every socket from its local endpoint: loopback only
      (`127.0.0.1`/`::1`/`localhost`), all interfaces (`*`/`0.0.0.0`/`::`), or
      one specific address (`SocketExposureClassifier`). The last two are
      labelled "LAN-reachable", never "public": without a router table LanFi
      cannot claim internet exposure. Exposure is a sortable table column.
- [x] Sample on a timer (30 s, cadence shared with the watcher) behind a
      persisted "Watch listeners" toggle, diff the set by PID + transport +
      local endpoint and post one notification per new or closed listener. The
      first sample after starting is a baseline, so starting the watcher does
      not announce every existing server.
- [x] **Optional user-recorded global hotkey that opens Connections; one
      owner, no default (5.6.6).** `Models/GlobalHotKey.swift` records a real
      key press (Escape cancels), builds the display string itself, and refuses
      a bare key or Shift alone, because Shift on its own only types a capital
      letter. The conflict rule is two-part: a fixed list of combinations the
      system or this app's menus already own (⌘Q, ⌘W, ⌘TAB, ⌘SPACE, ⌘K, ⌃⌘Q,
      ⌘⇧3/4/5, ⌘,) is refused by name, and `RegisterEventHotKey` reports
      `eventHotKeyExistsErr` when another app holds the combination —
      `Services/GlobalHotKeyCenter.swift` turns that into "Another app already
      uses that shortcut" and restores the previous shortcut instead of leaving
      the user with none. Registration uses Carbon rather than an event tap, so
      it needs no Accessibility permission. The shortcut fires the same
      `.lanfiShowToolkit` notification the menu bar and Diagnostics post, so the
      three entry points cannot drift; the notification names moved to
      `Utils/WorkspaceNotificationNames.swift` because `Services` posts them and
      the shared test target compiles `Services` without `Views`. Settings →
      General carries the card (Record / Clear / current combination), and the
      whole feature is inert until the user records something.

Delivered 2026-11-19: `Models/ListenerWatch.swift` (summary, diff, copy),
`Services/ListenerWatchService.swift` (`ListenerWatcher`, 30 s sampling through
`MonitorNotifier.shared`), the Exposure column and watcher card in
`Views/Toolkit/OpenConnectionsToolView.swift`, and `Tests/ListenerWatchTests.swift`.

Acceptance: starting `python3 -m http.server` produces a LAN-reachable row and
one notification within an interval; a loopback-only server is labelled local;
UDP listeners show the owning process.

### P3.2 — Continuous route monitor

TraceBar keeps a traceroute running and draws per-hop latency and loss as a
scrolling heatmap. LanFi runs traceroute, MTR and Visual Traceroute only on
demand, so route flaps and evening congestion have no history.

Tasks:

- [x] One continuous target at a time, reusing `MTRService` with a rolling
      window; slower cadence while the panel is closed.
- [x] Per-hop heatmap (time on x, hop on y, latency and loss colour) plus a
      destination sparkline in the menu bar.
- [x] Configurable latency/loss thresholds, route-change events, and the shared
      analysis target as the default destination.
- [x] Never more than one continuous monitor; state it in the UI.

Delivered 2026-11-21: `Models/RouteMonitor.swift` (samples, window statistics,
`RouteChangeDetector` with a two-sample flap guard, `RouteThresholdTracker` and
the cadence rule), `Services/RouteMonitorService.swift` (`RouteMonitor.shared`,
one loop, 180-sample window, 10 s active / 30 s panel closed / 60 s background,
route-change and threshold notifications), `Views/Toolkit/RouteMonitorToolView.swift`
(target field, scrolling heatmap, threshold controls, event log), the "Route"
menu-bar metric and popover card, a Route Monitor sidebar tool, and
`Tests/RouteMonitorTests.swift`.

Acceptance: a ten-minute run shows per-hop bands, emits one event when the path
changes, and keeps probe traffic below one round per second while idle.

### P3.3 — Connectivity watchdog

Online Check, Online Indicator, WhyFi and SimplePing all answer "is the
internet working right now?" in the menu bar. LanFi's dot and latency metric
only reflect the last diagnostics run, so a working link with a dead WAN looks
healthy until the user remembers to press Run.

Tasks:

- [x] `NWPathMonitor` for link changes plus two probes on a configurable
      interval (15 s–5 min), with configurable primary and fallback URLs; the
      cadence drops to `interval × 4` (capped at five minutes) while the app is
      inactive, like the throughput sampler.
- [x] Tri-state verdict: online, captive portal, offline. A captive portal is
      not "offline": a redirect, a 3xx or a 2xx HTML page without the
      `Success` marker is reported as a portal, and only a transport failure or
      a non-2xx/3xx status counts towards offline.
- [x] Transition notifications with per-direction toggles, a cooldown and the
      existing Monitor quiet hours; a single failed probe never flips a working
      connection to offline (two-strike hysteresis), and a lost network path is
      immediate.
- [x] A Shortcut/App Intent that probes and returns the current state; the
      menu-bar latency metric reads the watchdog's last sample instead of the
      diagnostics run, and the menu-bar icon follows the verdict.

Delivered 2026-11-19: `Models/ConnectivityWatchdog.swift` (verdict, classifier,
`ConnectivityWatchdogMachine`, `ConnectivityAlertPolicy`),
`Services/ConnectivityWatchdogService.swift` (NWPathMonitor, probe transport, timer),
Settings → General → Connectivity watchdog, and `Tests/ConnectivityWatchdogTests.swift`.

Acceptance: pulling the WAN cable flips the menu-bar state and posts exactly one
notification; a captive portal is labelled as such; a Shortcut can branch on the
state.

### P3.4 — VPN status and leak checks

VPN Peek shows whether a tunnel is up and whether DNS or IPv6 escapes it. LanFi
lists tunnel interfaces and resolves the public IP, but never checks the leak
path.

Tasks:

- [x] Detect an active VPN from the default route and `utun`/`ipsec`
      interfaces (`VPNDetector`, full and split tunnels); show provider-agnostic
      state (up, interface).
- [x] DNS indicator: parse `scutil --dns` resolver blocks, compare the resolver
      actually in use with the one the tunnel pushed, and flag a resolver
      outside the tunnel (`VPNDNSIntegrity`).
- [x] IPv6 indicator: flag a global IPv6 default route that does not belong to
      the tunnel while the tunnel is up (`VPNIPv6Integrity`).
- [x] Notify on an unexpected drop via a `vpnDropped` Monitor event and a
      `vpnLeak` warning; no provider API, no credentials. Both checks are
      labelled as indicators, not proof.

Delivered 2026-11-19: `Models/VPNGuard.swift` (detector, `scutil --dns` and
`netstat` parsers, both verdicts), `Services/VPNGuardService.swift` (20 s poll,
published `VPNGuardReport`, drop/leak events through `.lanFiSecurityEvent`),
two new `MonitorEventKind` cases with toggles, the Security Watch VPN card and
`Tests/VPNGuardTests.swift` (13 tests).

Acceptance: with a VPN up and no leak, both indicators are green; a test seam
that swaps the resolver or adds an IPv6 default route turns the matching
indicator red.

### P3.5 — DNS resolver benchmark and opt-in switching

DNS Easy Switcher ranks providers and switches the system resolver; WhyFi
offers two presets. LanFi can query any resolver but cannot compare them or
change the system setting.

Tasks:

- [x] Benchmark: median lookup time for a fixed name set against the system,
      Cloudflare, Google, Quad9 and custom resolvers (IPv4 and IPv6 where
      available), three rounds, ranked. (Shipped for IPv4 resolvers; the
      resolver pool in the card is the four built-ins.)
- [ ] Opt-in switching through `networksetup -setdnsservers` behind an admin or
      Touch ID prompt, with a one-click revert and a cache flush
      (`dscacheutil -flushcache` and `killall -HUP mDNSResponder`).
- [ ] Show the current resolver and the pending change before authorizing;
      never switch silently, never ship a preset as the default.

Acceptance: the benchmark ranks resolvers in under five seconds; switching
requires authorization, persists across a restart, and revert restores the DHCP
resolver.

### P3.6 — Per-app traffic history and domain attribution

FireWally shows per-app inbound/outbound counters, contacted domains and
hour/day history. Process Traffic shows only "since the previous sample" and
no domains.

Tasks:

- [x] Persist nettop deltas per app per hour and per day next to traffic
      accounting; retention 7 days, CSV export (`AppTrafficHistory`,
      `AppTrafficHistoryModel`, "App history" card on Process Traffic; LanFi's
      own traffic excluded).
- [ ] Attribute contacted domains from HTTP capture and cached reverse DNS, not
      payload; show the top domains per app.
- [ ] Exclude LanFi's own traffic, keep the privacy note and drop query strings
      from captured URLs.

Acceptance: after one day the screen shows today's bytes per app and its top
domains; no payload, cookies or full URLs are stored.

### P3.7 — Gateway ARP and DNS-hijack detection

Mojo Pulse flags ARP spoofing and DNS hijacking. Security Watch covers evil
twins, downgrades, randomized BSSIDs and deauth bursts, but nothing below the
Wi-Fi layer.

Tasks:

- [x] Watch the default gateway's MAC in the ARP table and raise a high-severity
      Security Watch event when it changes while the gateway IP stays the same
      (`GatewayARPWatch`, sampled every 2 minutes; a missing ARP entry is
      treated as unknown, never as a change).
- [x] Compare the system resolver's answer for a canary host with the answer a
      public resolver returns directly (`ResolverIntegrity`); a disjoint answer
      is a warning on the Security Watch screen and in the Monitor log.
- [x] Feed both events into the Monitor event log and the existing notification
      rules through `.lanFiSecurityEvent` → `MonitorViewModel.ingestExternal`,
      with `gatewayChange` / `dnsMismatch` toggles in the alert sheet.

Delivered 2026-11-19: `Models/GatewayIntegrity.swift`,
`Services/GatewayGuardService.swift`, new `MonitorEventKind` cases, the Security
Watch integrity card and `Tests/GatewayIntegrityTests.swift` (11 tests including
the spoof/no-spoof seam).

Acceptance: a test seam that changes the gateway MAC produces one event and one
notification; an unchanged MAC produces none; a resolver mismatch is labelled as
a warning, not an attack.

### P3.8 — Wired/Wi-Fi link automation

LanGuard disables Wi-Fi while a physical Ethernet link is up and restores it on
unplug, edge-triggered and wake-aware. LanFi only reads interface state.

Tasks:

- [x] Observe physical Ethernet transitions; when a wired link is primary,
      optionally power Wi-Fi off, and restore it on unplug (`LinkAutomation`,
      10 s poll of `networksetup -listallhardwareports` + `ifconfig status`).
- [x] Edge-triggered only: a manual Wi-Fi change wins, the policy forgets its
      own intent when the user re-enables Wi-Fi while docked, and the intent is
      re-applied once after wake.
- [x] Adapter allow-list that excludes VPN, VM and bridge interfaces
      (`LinkAutomationClassifier`); a master pause in Settings; off by default
      with an explanation of the write action next to the toggle.

Delivered 2026-11-19: `Models/LinkAutomation.swift` (policy, hardware-port
parser, `ifconfig`/airport-power parsers),
`Services/LinkAutomationService.swift` (poll, wake observer, `networksetup
-setairportpower` write with an explicit error, notification per change) and
`Tests/LinkAutomationTests.swift` (12 tests covering every edge case).

Acceptance: plugging Ethernet disables Wi-Fi once, unplugging restores it, a
manual disable while docked survives a re-plug, and pause stops all toggling.

### P3.9 — SSH quick launch from saved sensors

Shuttle turns a JSON host list into one-click Terminal sessions. Remote Sensors
already store host, user, port and identity file but only run probes.

Tasks:

- [x] Context action on a saved sensor (sidebar row and detail header) and on a
      LAN device whose scan found port 22 open, opening Terminal with
      `ssh -p <port> -i <identity> user@host`. `SSHLaunchCommand` quotes every
      field for the shell, and the AppleScript hand-off escapes quotes and
      backslashes again.
- [x] A copy-command alternative for users who keep their own terminal.
- [x] No password storage and no key generation: the command only carries the
      key path the sensor already had, and the UI says so.

Delivered 2026-11-19: `Models/SSHLaunch.swift` (command builder and quoting),
`Services/TerminalLauncher.swift` (`osascript` hand-off and clipboard copy), the
sensor row/header actions and the LAN Scanner context menu, plus
`Tests/SSHLaunchTests.swift` (9 tests incl. quoting and AppleScript escaping).

Acceptance: the action opens Terminal pre-filled for a saved sensor and the
command contains no password.

### P3.10 — Plain-language service descriptions

FireWally translates domains and processes into plain language, with Apple
Intelligence for unknown ones. Connections shows raw process names and
endpoints.

Tasks:

- [x] Bundle an offline map of common domains and processes to a one-line
      description (`ServiceDescriptionCatalog`: 43 domain patterns and 18
      process names, exact entries before suffix entries), so the feature works
      on macOS 13 without a model.
- [x] When Foundation Models is available (macOS 26+), generate a description for
      unknown domains on device through `ServiceDescriptionResolver`; opt-in
      (`LanFi.descriptions.model`, off by default), no upload, and a
      model-unavailable fallback to "Unknown service".
- [x] Show the description in Connections (Service column per process) and on
      the HTTP traffic screen (Service column plus the inspector row), with the
      raw host one click away via a copy button.

Acceptance: known domains explain themselves offline; unknown domains read
"Unknown service" unless the on-device model is enabled.

Delivered 2026-11-19: `Models/ServiceDescription.swift`,
`Services/ServiceDescriptionResolver.swift`, the Service columns and the
inspector row, the Settings toggle (only shown when the model is available) and
`Tests/ServiceDescriptionTests.swift`.

Not planned from this source: packet-filter enforcement, ad blocking with a
root certificate, VPN clients, share automounting, cross-device file transfer,
CI/commute monitors and a system posture audit. The reasons are in
[`ONMYMENUBAR_NETWORK_REVIEW_2026-11.md`](ONMYMENUBAR_NETWORK_REVIEW_2026-11.md)
and in the non-goals below.

## P4 — Bettbox review (Another Better Network Toolbox, 2026-11-19)

Source: <https://github.com/appshubcc/Bettbox> (Flutter GUI over the Mihomo
Go core, GPL-3.0, macOS 12+ Intel/Apple Silicon, Windows, Linux, Android).
LanFi does not route or proxy traffic, so the proxy half of that app — TUN,
subscriptions, protocol handlers, rule routing, media-unlock checks — is out of
scope. What is worth reading is how it treats **long-running supervision, DNS
debugging and tool discovery**; those parts fit LanFi's analyzer and toolkit.

**Licence:** Bettbox is GPL-3.0. Nothing below is copied — no source, strings or
assets. These are behaviour and interaction patterns to re-implement in Swift.
Only the idea, the measurements and the UX shape carry over.

### P4.1 — Privileged helper with a hash-pinned binary

*What Bettbox does.* `services/helper` is a small Rust service (`src/ipc.rs`,
`src/rpc.rs`, `src/ops.rs`) that installs as a system service and exposes RPC
over a local channel. Before it starts anything it opens the requested
executable, hashes it (SHA-256, streamed in 64 KiB blocks, cached by
size+mtime) and compares the digest with a value compiled into the helper
(`env!("TOKEN")`); a mismatch is logged and refused. It then spawns the process,
binds it to a Job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` so it cannot
outlive the helper, keeps a bounded in-memory log ring, and offers process
priority and memory-priority operations restricted to an allow-list of
executable names.

*Why it matters for LanFi.* Anything that needs root today (BPF capture without
`tcpdump` setuid, raw sockets, `pf` inspection) is refused or shelled out with
an admin prompt each time. A signed helper that only executes one hash-pinned
binary is the pattern that makes such a feature shippable without handing the
user a general root shell.

*Where it would live.* `Helper/` target (Swift or Rust) plus a
`HelperClient` in `Services/`; `SMAppService.daemon` registration, launchd job,
NSXPCConnection instead of a pipe, code-signing requirement checked on both
sides.

*Decision.* Not in this cycle: it contradicts the current "no elevation, no
persistent daemon" constraint and needs Developer ID first (P0.1). Recorded so
the capture work has a safe shape when it is attempted.

### P4.2 — Supervised worker lifecycle: readiness, retry, auto-restart

*Delivered in 5.5.5 (core):* `Services/SupervisedProcess.swift` launches a
long-lived child, treats readiness as a real answer with a timeout, retries
once with fresh arguments, restarts after an unexpected exit at most once per
rate-limit window and only while `isHealthy()` agrees, and shuts down with
SIGTERM then SIGKILL in an idempotent, serialised path. `Tests/
SupervisedProcessTests` covers a child that exits immediately (found and fixed
a real defect: an exit during startup used to be reported as "running"), one
that never answers, the fresh-argument retry, the automatic restart, the
crash-loop throttle and the unhealthy-helper refusal.

*Completed in 5.6.4 (remote helpers):* `Services/SupervisedCommand.swift` runs
one short-lived child under `SupervisedProcess` and returns its status, stdout
and stderr, draining both pipes while the child runs. The remote capture
(`ssh`, `scp`, the cleanup `ssh`) and the remote sensor scan both go through it
now, so a hung ssh has a hard limit (capture duration + 60 s, sensor 60 s) and is
stopped with SIGTERM then SIGKILL instead of leaving the screen on "scanning…"
forever. Two real defects came out of the wiring and are fixed: a one-shot
command that finished during the readiness window was reported as a failed
launch, and reading stderr to end-of-file before stdout deadlocked as soon as
the child filled the unread pipe — which `system_profiler` JSON can do.
`Tests/RemoteCaptureSupervisionTests` covers success, stderr propagation, the
timeout, a missing executable, and 400 KB on both streams.

*What Bettbox does.* `lib/clash/service.dart` runs the core as a long-lived
child and treats its IPC transport as the readiness signal:

- the transport is a Unix domain socket in the temp directory with a random
  token in the name (`Bettbox_<random>.sock`) or, where that is unavailable,
  loopback TCP on an ephemeral port — no fixed port, no world-readable socket;
- "ready" means the socket connected **or** the process exited (whichever comes
  first) within a 6 s production / 15 s development timeout;
- if the child does not connect, the transport is rebound to a fresh socket and
  the launch is retried once with the new argument;
- an unexpected disconnect triggers one automatic restart after 2 s, rate
  limited to one attempt per minute, and only while the helper reports healthy;
- health is a real RPC (`getIsInit`) with a 2 s timeout, not "the process is
  alive"; shutdown sends SIGTERM and escalates to SIGKILL after 2 s, and the
  shutdown path is idempotent so a second call cannot double-kill;
- restarts are serialised through a `Completer`, so concurrent callers await the
  same restart instead of starting several workers.

*Why it matters for LanFi.* The remote-sensor and capture helpers are spawned
processes already, and they have neither a readiness probe nor a restart policy:
a hung `tcpdump`/sensor looks like "no data". The rate-limited restart, the
idempotent shutdown and the "await the same restart" rule are directly reusable
in `Services/`.

*Where it would live.* A `SupervisedProcess` type in `Services/` (start, readiness
predicate, timeout, retry-with-new-transport, shutdown escalation), unit-tested
with a fake child that exits, hangs and closes late.

### P4.3 — DNS console: record types, encrypted transports, compare mode

*What Bettbox does.* `lib/pages/toolbox/dns_query.dart` offers A, AAAA, CNAME,
HTTPS, TXT, MX and NS as chips, three resolution modes (follow the running
tunnel, system resolver, custom server) and a preset list mixing plain IPs with
`https://…/dns-query` (DoH), `tls://dns.google` (DoT) and
`quic://dns.adguard-dns.com` (DoQ). A **Compare** switch sends the same query to
all applicable modes in parallel and renders one card per mode: RCODE and
elapsed milliseconds in the header, one row per record with type badge, value,
TTL, and — for A/AAAA — country, city, ASN and ISP, clickable into an IP detail
sheet. A note under the answers explains *why* the answer looks like that
(hosts hit, fake-ip on/off with its range, which outbound the domain would take),
which is the part LanFi's plain record table lacks.

*Where it would live.* `Views/Toolkit/DNSToolView.swift` gains a Compare card
(the benchmark card already measures resolvers; this explains a single name),
`Services/DNSLookupService` gains DoH/DoT via `URLSession`/`NWConnection`,
`Models/DNSQueryComparison` holds the per-resolver result, and the record table
reuses `AppTable` with a TTL column. The route explanation maps to LanFi's
interface, gateway and DNS answers instead of proxy outbounds.

*Caution.* LanFi must not flush the system DNS cache on the user's behalf; if a
"flush cache" affordance is ever added it stays a documented, admin-prompted
action, not a one-tap button.

*Delivered in 5.5.6:* `Services/Toolkit/DoHDNSClient.swift` resolves through
the `application/dns-json` endpoints (Cloudflare, Google, or a custom HTTPS
endpoint) and maps the JSON answers onto the same `DNSRecord` the UDP path
produces, so the comparison compares answers rather than encodings. The DNS
tool gained a **Compare** button: one query goes to system/Cloudflare/Google
over UDP and to Cloudflare/Google over DoH in parallel, and a single
`AppTable` card shows resolver, transport, the answer and the time, with a
status pill saying whether the answers agree. Agreement is compared on the set
of answer values, so record order and TTL differences do not produce false
alarms, while an empty answer next to a populated one does count — that is the
hijack case. Failed resolvers are reported as rows with their error and
counted in the footer instead of being dropped.

*Delivered in 5.6.1 (DoT):* `Services/Toolkit/DoTDNSClient.swift` resolves over
DNS-over-TLS (RFC 7858) with `NWConnection`: TLS to the resolver on port 853,
SNI set to the resolver's name so the certificate check has something to match,
two-byte length-prefixed framing (`DoTFraming`, tested with partial and doubled
reads) and the same `DNSMessage.parseResponse` the UDP path uses, so the
comparison still compares answers rather than encodings. The comparison runs
Cloudflare and Google over DoT next to the three UDP resolvers and two DoH
endpoints, with the rows ordered plain → DoH → DoT. A live probe test
(`LANFI_LIVE_TESTS=1`) resolved `example.com` over TLS in 303 ms and caught a
real defect on the way: the connection object was deallocated before the
handshake finished, leaking the continuation and hanging the lookup forever.
*Delivered in 5.6.2 (address annotation):* `Services/Toolkit/DNSAddressEnricher.swift`
annotates the addresses of an A/AAAA answer with country, ASN and network
through the GeoIP client the Whois screen already uses. It runs after the
records appear, so a slow lookup never delays the table; it deduplicates the
addresses (a CDN name often returns the same address twice), caps itself at
four lookups per answer, ignores values that are not addresses, and a failed
lookup leaves that cell empty instead of hiding the record.
`Models/DNSAddressAnnotation.swift` holds the formatting ("🇺🇸 US · AS15169 ·
Google LLC") and is covered by `Tests/DNSAddressAnnotationTests` together with
the enricher's dedupe, limit and failure behaviour. The annotation sends the
resolved addresses to a third-party GeoIP service, which is why it is limited
and only runs for address records.

*Delivered in 5.6.3 (why this answer):* `Models/DNSAnswerExplanation.swift`
turns the shape of an answer into short notes under the table, using only what
LanFi can see. It flags an address in 198.18.0.0/15 (the fake-IP range proxy
tools borrow) and an answer made entirely of private addresses, explains a zero
TTL, compares the answer with the same question asked of the system resolver —
the honest local equivalent of Bettbox's hosts/fake-ip/outbound note — and says
when the addresses belong to several networks, which is what a content network
looks like. Every rule is pure and covered by `Tests/DNSAnswerExplanationTests`;
the second query runs in the background with a 3 s timeout and its failure is
silence, not an error row. Still open from this item: DoQ (needs QUIC, not just
a TLS stream).

### P4.4 — NAT type and STUN reachability test

*What Bettbox does.* `lib/pages/toolbox/nat_test.dart` runs a STUN session
against a preset or custom `host:port` (validated by regex, port 1–65535) and
classifies the result as Open, Full-cone (NAT1), Restricted (NAT2),
Port-restricted (NAT3) or Symmetric (NAT4), with a separate mapping behaviour
(independent / address / address-port / dependent) and filtering behaviour. It
shows the external IP and port, the local IP, whether the port is preserved or
randomised, latency and loss, and a phase indicator while binding, filtering and
mapping are probed.

*Why it matters for LanFi.* Port Scan answers "is the port open on this host";
nothing answers "will anything from the internet reach me". NAT classification
explains failures in port forwarding, game consoles, VPN handshakes and
server hosting — a natural companion to the existing Port Scan and Gateway
cards, and the only tool on this list LanFi has no equivalent of at all.

*Where it would live.* `Services/STUNTester.swift` (RFC 5389 binding requests to
two servers, RFC 5780 mapping/filtering probes over `NWConnection` UDP),
`Models/NATProfile.swift` (pure classification, unit-testable with recorded
responses), `Views/Toolkit/NATTestToolView.swift`, and a `ToolboxTool` entry.
All traffic goes to public STUN servers only; the server list stays editable and
the default set is documented.

*Delivered in 5.6.0 (mapping half):* `Services/Toolkit/STUNMessage.swift` builds
RFC 5389 binding requests and decodes XOR-MAPPED-ADDRESS and the deprecated
MAPPED-ADDRESS (IPv4 and IPv6), `Services/Toolkit/STUNTester.swift` probes two
servers **from one socket** — two requests to the first prove the mapping is
stable, the third destination shows whether the router reuses it —
`Models/NATProfile.swift` classifies mapping behaviour and the verdict
(no NAT / cone / symmetric / blocked) as pure data, and
`Views/Toolkit/NATToolView.swift` plus a `NAT Test` tool entry show the local
and external endpoints, port preservation, latency per probe and a copyable
report. The classification is deliberately narrower than the reference app's:
filtering behaviour needs a server that sends back to the mapped address, so it
is reported as "not probed" instead of guessed, and cone NAT is not split into
full/restricted/port-restricted without that probe. The default servers
(`stun.l.google.com:19302`, `stun.cloudflare.com:3478`) are listed in
`STUNEndpoint.builtIn`; both answered a live binding request from this
machine. `Tests/NATProfileTests` covers the message codec, the mapping
classification and every verdict.

### P4.5 — Command palette over tools and settings

*Delivered in 5.5.3:* `Models/CommandIndex.swift` indexes every available
tool, every `SettingsSection` and the eight Wi-Fi workspace panels; ranking
(exact title → prefix → substring → keyword → subtitle → category) and the
coverage of the index are covered by `Tests/CommandIndexTests`. `⌘K` opens
`Views/CommandPaletteView.swift` from the View menu; picking a hit selects a
tool, a bottom tab, or opens the Settings window on the matching page.

*Completed in 5.5.7:* keyboard navigation (↑↓ with wrap-around, Return opens
the highlighted row, Esc closes; hover follows the mouse and clicking still
opens the row), covered by `Tests/CommandPaletteSelectionTests` over
`CommandPaletteSelection`. Settings keywords are localized in all five locales
(`settings.keywords.<section>`, one comma-separated string per page), so
«анонимная статистика» finds Privacy and «бенчмарк резолверов» finds
Diagnostics; `Tests/CommandIndexTests` reads the shipped `.strings` tables and
asserts every page has keywords everywhere. The Settings hop no longer uses a
string selector from the palette: `Models/SettingsRouter.swift` carries the
requested page, `Views/SettingsOpenerRegistration.swift` registers SwiftUI's
own `openSettings` action on macOS 14+, and `SettingsView` applies the pending
page on appear or change, consuming it once so reopening Settings does not jump
back. `Tests/SettingsRouterTests` pins the request/consume semantics; the
window-open itself still falls back to the selector on macOS 13.

*What Bettbox does.* `lib/views/tools.dart` indexes every screen and every
setting into `_SearchItem` records (title, subtitle, category, destination),
rebuilds the index only when the navigation set changes, filters with a 300 ms
debounce, groups hits by category (Settings / Config / Network / NTP / Sniffer /
…), and opens the target page or sheet directly. The palette is the primary way
to reach a setting on a phone-sized screen.

*Why it matters for LanFi.* The app now has 11 settings tabs, ~20 toolkit tools
and a sidebar; finding "anonymous statistics" or "resolver benchmark" means
knowing where it lives. A ⌘K palette over a declarative index is cheap and is
the single largest discoverability win on this list.

*Where it would live.* `Models/CommandIndex.swift` (id, title, keywords,
category, action), a `.searchable`/sheet palette in `Views/`, opened by ⌘K and
from the toolbar, with every settings page and `ToolboxTool` registering an
entry. Tests cover ranking (exact title before keyword) and the empty state.





### Not planned from this source

| Feature | Why not |
| --- | --- |
| TUN device, strict route, ICMP forwarding | LanFi observes traffic; it never intercepts or forwards it. |
| Proxy protocols, subscriptions, rule routing, policy groups | Out of the product's scope and a security liability without a signed core. |
| Media-unlock checks | Requires third-party streaming APIs and accounts. |
| Code-forge editor (Rust/Flutter code editor plugin) | LanFi has no scripting surface to edit. |
| JS override scripts with a generated GUI | Same reason: no config language to expose. |
| Doze/mobile background adaptation | macOS-only product. |
| Android/TV widgets and HarmonyOS packaging | Not a target platform. |
| In-app affiliate links and sponsor blocks | Not appropriate for a paid utility. |

## Design and presentation (оформление)

Everything below is about making delivered capability legible. It is not
cosmetic polish at the end: D1 and D3 change files that every screen imports, so
they should land early and in small slices.

Current state: `Views/Toolkit/ToolkitComponents.swift` defines
`ToolkitCard`, `ToolkitSectionLabel`, `ToolkitStatusPill` and `ToolkitTone`, but
they are used only by toolkit screens. The Wi-Fi workspace and the settings
windows repeat the same card recipe with different numbers (corner radius 8/10/12,
stroke `Color.secondary.opacity(0.12)`/`0.15`/`0.2`, tinted `Color.orange
.opacity(0.08..0.10)` warning blocks). There is no token layer, no shared
stat/hero component, and no density option for the AppKit table.

- [ ] **D1 — Design tokens and shared components.** Tokens, components and the
      first consumer shipped 2026-11-16; migrating the remaining screens is open.
      - [x] `DesignTokens`: spacing scale (4/8/12/16/24), corner radii (6/10/14),
            stroke opacities, control heights, and a semantic palette (`ok`,
            `warn`, `bad`, `info`, `muted`, band colours for 2.4/5/6 GHz,
            quality scale green→amber→red) defined once with light/dark and
            increased-contrast variants.
      - [x] **One theme file.** `Views/Theme.swift` now holds spacing, radii,
            strokes, layout geometry, semantic typography (`Typography`),
            surfaces (`Surface.card`, `.panel`, `.cardStroke`, `.border`),
            control metrics (`Control.height`, `.iconWidth`, `.horizontalPadding`)
            and the palette. `DesignToken` and `AppPalette` are aliases of it, so
            the definitions exist once while 800+ call sites keep working.
      - [x] **One card and one section label.** `ToolkitCard` delegates to
            `AppCard`, and both label types share `.appSectionLabel()`; the
            toolkit's second fill/radius/stroke recipe is gone. Buttons and icon
            buttons read their height, padding and icon size from
            `Theme.Control`/`Theme.Typography`. Panels that need a tinted or
            material card still draw it, but from theme values and
            `.appCardSurface(fill:)`.
      - [x] **Tinted and material cards (5.5.8).** `appCardSurface` takes
            `tint:` and `strokeWidth:`; the tint supplies both the fill
            (`Theme.Surface.tintFill`, 12%) and the hairline
            (`Theme.Surface.tintStroke`, 30%), so a band-, status- or
            category-coloured card is the same object at the same radius. The
            remaining bespoke recipes moved onto it: the Protocols band and
            status cards (their gradients are gone), the Interfaces card (its
            increased-contrast 2 pt stroke is now the `strokeWidth` argument),
            the Insights nested panels and accent/green blocks, the Visual
            Traceroute node, progress and detail cards, the Survey coverage
            chips and the survey window card, the survey map frame, the
            multi-floor plan cards and badge, the Help topic banner, the QR
            placeholder and the two settings rule editors. The only literal
            white fill left is the QR code canvas itself, which has to stay
            white for scanners to read it.
      - [x] **Token lint (5.6.5).** `Tests/DesignTokenLintTests` scans every file
            in `Views/` except `Theme.swift` and fails on a literal
            `.cornerRadius(8)` or on a role-named translucent fill such as
            `Color.orange.opacity(0.08)`; a tint that comes from data is not
            flagged. The rule is written down in `CONTRIBUTING.md` → Design
            tokens. Landing the test meant cleaning up what it found: four
            literal radii (Insights chart bars, offline-capture reply block,
            inspector BSSID chip, inspector stat tile) and eleven literal fills
            (table stripes, search-field chip, menu-bar warning block, panel
            hairline, Protocols warning block, process-traffic and connections
            accent chips, Internet Check row, two device-shelf chips, inspector
            row, empty-state failure block), with `Surface.controlFill` and
            `Surface.dangerFill` added so nothing had to keep its own number.
            The test was proved by planting a violation and watching both rules
            fail. A component-level "every tool draws an AppCard root" assertion
            is deliberately not written: it would need the view tree, and the
            classes it would catch are already impossible to add without failing
            the token lint.
- [ ] **D2 — Hero RF overview, first run and empty states.** The overview,
      first run and empty states shipped 2026-11-16; the menu-bar open target is
      still open.
      - [x] All-band overview (P1.10): 2.4/5/6 GHz columns, AP spans with overlap
            shading, connected AP highlighted, recommended channel as a marker,
            legend in plain words ("channels other networks also use are
            shaded").
      - [x] The `MenuBarExtra` "Open LanFi" button now selects the Wi-Fi
            workspace and bottom tab 9 (All Bands), so the overview is the first
            thing on screen.
      - [x] First-run screen: what LanFi shows, why Location is needed and the
            privacy stance, with "Allow Location Access" as the primary action.
            Shown once (`LanFi.hasCompletedFirstRun`).
      - [x] Empty/error states for no scan, no permission, no Wi-Fi hardware,
            scan failed, stale data and over-filtering, each with an action.
            Decided by the pure `WorkspacePlaceholderEvaluator`.
- [x] **D3 — Table presentation.**
      - [x] Row density setting (compact / regular / comfortable) persisted, with
            the AppKit row height and font size driven from it; default to the
            current height so nothing shifts for existing users.
      - [x] In-cell micro-visuals: signal bar and quality bar with semantic
            colour, painted beside the number in their own gutter. Band and
            security chips were dropped — see the presentation rules below.
      - [x] Sorting and grouping affordances visible in the header: AppKit's own
            sort indicator plus the grouping marker. No second arrow is added
            to the header text.
      - [x] Sort menu generated from the visible table columns, excluding
            identity columns, instead of a hand-maintained option list.
      - [x] Relative "time ago" formatting for first/last seen when the value is
            under 24 h, absolute otherwise; AirRadar's 8.0 note is exactly this.
      - [x] Wording audit with plain alternatives for domain terms next to the
            column header tooltips ("BSS Load", "PMF", "DFS", "puncturing").
- [ ] **D4 — Chart and inspector visual language.**
      - [x] One chart style used by the history, occupancy, Canvas spectrum and
            toolkit latency graphs: `ChartStyle` now drives grid colour/dash,
            axis labels, hover cursor and tooltip surfaces; Swift Charts screens
            share the same `AxisMarks`, and the Canvas spectrum draws its grid,
            lane dividers, hover line and readouts from the tokens.
      - [x] Inspector restructure: the Link block is pinned above the scrolling
            detail sections and covers rate, PHY, width, band/channel, streams
            (NSS capability), noise, cipher and BSSID.
      - [x] History chart mode switch: signal / noise / both (P2.6). Noise is
            dBm-only, so percent mode stays signal-only.
- [x] **D5 — Menu-bar and window chrome.**
      - [x] Menu-bar sparkline (P0.6) drawing moved into the pure
            `SparklineGeometry` and the shared `ChartStyle` sparkline tokens;
            the `MenuBarExtra` label renders monochrome (`symbolRenderingMode`,
            `.foregroundStyle(.primary)`) so it stays legible as a template
            image in light and dark menu bars, and VoiceOver gets one combined
            label.
      - [x] One toolbar treatment across the Wi-Fi workspace and toolkit:
            `ToolbarIconButton` and the `appToolbarChrome` modifier share the
            control height, radius and stroke, and the workspace refresh/pause,
            settings, export, inspector, diagnostics and location controls plus
            the toolkit Help button all use them.
      - [x] Icon audit: every icon-only control in the workspace toolbar, chart
            toolbars, filter bar, spectrum/history zoom controls, device shelf,
            remote sensors and uptime carries both a tooltip and an
            accessibility label; the `Planned` badge and the toolkit tone/dot
            palette now use the semantic `AppPalette` roles.
- [ ] **D6 — Settings, Help and onboarding.**
      - [x] Settings is no longer 11 tabs: a grouped sidebar (Application /
            Analysis / Integrations) with the last section remembered in
            `LanFi.settings.section`, over the unchanged screens. Deep links use
            the same settings window.
      - [x] Appearance, density and the menu-bar meter live in General, next to
            the display and toolbar options.
      - [ ] Help window: task-oriented sections with one screenshot each, plus an
            in-app "what is this?" popover on the main chart.
- [ ] **D7 — Accessibility visual pass.** (partial: palette, reduce motion
      and the inspector/protocol VoiceOver stops are done; text scaling and a
      measured contrast audit remain open)
      - [x] Colour-blind-safe palette option: Settings → Appearance toggles the
            Okabe–Ito blue/amber/magenta roles for status, quality and band.
            Semantic labels remain alongside colour. The flag is cached in
            `AccessibilityPalette` (no `UserDefaults` read while drawing a
            cell) and the toggle rebuilds the main window subtree, so the
            palette applies without a relaunch. `AccessibilityPaletteTests`
            covers the five hues, the defaults mirror and the live resolution.
            Full 4.5:1 contrast audit remains open.
      - [x] Reduce motion: every explicit animation in `Views/` is behind
            `accessibilityReduceMotion` — the spectrum cross-fade, traceroute
            hop transitions, filter-bar expansion and the inspector slide
            (verified by grepping `.animation(`/`withAnimation`).
      - [ ] In-app text scaling. `dynamicTypeSize` is documented as having no
            effect on macOS text size (verified on a snapshot), so this needs a
            custom font-metrics/whole-app pass rather than a dead switch.
      - [~] VoiceOver pass: protocol block cards, MLO link rows, regulatory
            facts and co-located radio buttons now expose one combined stop or
            an explicit label; the tool tables and the help window still need a
            hands-on run.
- [ ] **D8 — Release visual assets.**
      - [x] A repeatable screenshot script (seeded data, fixed window size, light
            and dark) so README, site and release notes never go stale.
            `scripts/visual-check.sh` passes `--demo`, which seeds Wi-Fi, survey
            and uptime fixtures from `Utils/DemoData.swift` (Debug-only, never
            persisted) and blocks live scans.
      - [x] Refresh `docs/images/` and `site/` gallery from that script; the
            gallery phase captures the four toolkit screens at a fixed
            1180×760 pt window and exports WebP to both trees. The icon
            generator (`scripts/make_icon.swift`) stays the only icon source.

**Presentation rules (decided 2026-11-16).**

- In-cell micro visuals are allowed **only** in the Signal and Quality columns,
  and a bar must sit beside its number, never underneath it. Do not implement
  bars, chips or badges for Band, Security or any other column: those values are
  categorical and already legible as text, and the decoration read as a second,
  competing legend. `TableMicroVisualFactory` returns `nil` for every other
  column and `Tests/TablePresentationTests.swift` enforces the rule.
- The table header has exactly one sort indicator: AppKit's, driven by the sort
  descriptor. Never append arrows to the header text as well.
- The sort menu is built from the visible table columns in column order,
  excluding identity columns (`ColumnId.isSortableOption`: network name, BSSID,
  AP name, annotations). Do not reintroduce a hand-maintained option list.

Acceptance for the D-series: a new screenshot of the default window shows the
all-band overview, semantic chips and consistent cards; no screen in
`Views/` hand-rolls a card, radius or tint; light, dark and increased-contrast
builds all pass the contrast check; and every new string ships in all five
locales.

---

## Engineering work

### Modularity

- [x] Seed `LanFiCore` as a SwiftPM library with typed settings and its own
      `swift test` target. Models, parsers, analyzers and stores still live in
      the app target.
- [~] Extract the rest of `LanFiCore` (models, parsers, analyzers, stores) and
      `LanFiProbes` (ICMP/TCP/DNS/TLS); this needs a public-API pass.
      Delivered 2026-11-21: `ToolTarget`, `MTRHop`/`MTRReport` and the whole
      route-monitor model layer moved into `LanFiCore` with a public API;
      `Models/ToolkitModels.swift` now imports the package. What remains is the
      Wi-Fi model layer (`NetworkModel`, `InformationElement`) and the
      analyzers/stores, which reach into CoreWLAN, AppKit and the scanner and
      need a Foundation-only seam before they can move.
- [x] Stop listing sources three times in `project.yml`; app, tests and CLI
      depend on packages instead. `targetTemplates.shared` lists `Models`,
      `Services` and `Utils` once, and the three targets inherit it. The only
      Sparkle reference (`UpdaterController`) moved to `App/`, so the CLI links
      the shared sources without the updater framework and the test bundle no
      longer depends on Sparkle.
- [x] Split `ToolkitViewModel` (1311 → 44 lines + 15 focused files).
- [x] Split `MainTableView` (1314 → 252 lines + 6 focused files).
- [x] Split `AnalyzerViewModel` (1490) and `MCPToolkit` (1280).
      `AnalyzerViewModel` is now a 279-line core plus `AnalyzerViewModel+`
      extensions for scanning, filtering, workspace queries, sessions, export
      and persistence; `MCPToolkit` is a 73-line catalogue plus extensions for
      definitions, arguments, scan analysis, probes, service tools and encoding.
      Splitting moved members to internal access, so the shared state is set
      from one module-internal surface rather than file-private helpers.
- [x] Centralize `ToolboxTool` metadata in one `ToolRegistry` table, with a
      test that every tool has exactly one descriptor.
- [x] Move view routing and the MCP tool spec into the registry so a new tool
      is one descriptor plus one view. `ToolDescriptor.screen` (a `ToolScreen`
      case) drives the detail switch, tabbed tools share a route (`.connections`)
      and `ToolDescriptor.mcpTools` names the specs in `MCPToolRegistry`
      (`Models/MCPToolSpec.swift`), which now renders `MCPToolkit.definitions`.
      `ToolRoutingTests` enforces route coverage, distinct sidebar screens,
      known MCP names, unique/well-formed specs and the advertised count.
- [x] Introduce typed `AppSettings` with defaults, legacy migration and
      export/import; General Settings already uses it.
- [x] Migrate the remaining string keys (monitor, capture, survey, reports,
      alerts, MCP, automation, display, interface, layout) into `AppSettings`.
      `AppSettingsKey` is the only spelling of a persisted key: 73 cases, used
      by every `UserDefaults`/`@AppStorage` call site. Typed sections decode
      tolerantly, migrate from the legacy keys, mirror back on save, and are
      refreshed from their key before a save so direct writers are never rolled
      back; `importData` remains authoritative. Covered by
      `AppSettingsMigrationTests` (9 tests) plus the original 8.
- [x] Dependency seams (clock, settings storage, scanner, notifications, file
      store) and Swift 6 strict concurrency for the core module. `LanFiCore`
      builds with `swiftLanguageMode(.v6)` and injects `Clock`,
      `SettingsStorage`, `NotificationPosting` and `FileStoring`;
      `AppSettingsStore` also takes them and posts
      `Notification.Name.lanFiSettingsDidChange`. The app exposes the same
      seams: `WiFiScanning` for `AnalyzerViewModel`, `Clock` and
      `MonitorNotifying` for `MonitorViewModel`, `UserNotifying` already
      existed.
- [x] Make `swift-format` blocking in CI and run `swift test` for the core
      package.
- [x] Add a macOS 13/14/15/26 matrix, UI smoke tests and performance budgets.
      The test job runs the core package plus the app suite on the images
      GitHub still provides (`macos-15`, `macos-26`); 13 and 14 no longer have
      runner images (a job on either label is cancelled before its first step),
      so the 13.0 deployment target is compiled and tested by the images that
      remain.
      `scripts/ui_smoke.sh` runs `--ui-smoke`, which lays out every available
      tool screen and both menu-bar surfaces headlessly, then the bundle check.
      Screenshot capture stays an opt-in local aid (`LANFI_UI_SNAPSHOTS=1`)
      because it needs a WindowServer session.
      `Tests/PerformanceBudgetTests.swift` holds generous budgets for a
      300-network analysis, the JSON export and a 180-sample route window, so
      the same tests run locally and on the runner.

### Settings

- Scanning: mode, bands, adaptive interval, pause on battery/background,
  channel dwell.
- Monitoring: retention, sampling, event selection, thresholds, quiet hours,
  menu-bar metric.
- Capture: helper, default interface, channel plan, auto-analyze, storage
  folder and limit, redaction.
- Survey: units, heatmap detail, default wall/floor materials, antenna library.
- Reports: format, sections, branding/logo, schedule, redaction.
- Privacy: external lookup toggles, crash-report opt-in, export redaction.
- Units: dBm/%/both, MHz/GHz, date/time, CSV delimiter.
- Advanced: full settings export/import, reset, log level, update channel,
  feature flags.
- Accessibility: colorblind-safe palette, reduce motion, font size.
- Automation: launch at login, Shortcuts, MCP autostart.

---

## Delivered in the forty-third slice (2026-11-21)

Tables fixed at the shared builder instead of screen by screen. `AppTable` had
no column rules (only a horizontal divider), no cell padding (text sat against
the column edge), a `caption2` header in every screen, no way to resize a
column, and a trailing `Spacer` that ate the leftover width — so all columns
huddled at the left of a half-empty card. The builder now paints a header band
with a 12 pt semibold `Theme.Typography.tableHeader`, draws
`Theme.Surface.divider` rules between columns in both the header and the rows,
pads every cell, and reads widths from `Models/TableColumnLayout.swift`, which
fills the card, honours a hand-dragged column and borrows from the flexible ones
down to their minimums before scrolling. A 7 pt grab strip on each boundary
resizes; a plain header click still sorts.

## Delivered in the forty-second slice (2026-11-21)

Site-survey plan repaired. Three defects made the screen unusable rather than
unfinished: `SpatialTapGesture` delivered no clicks at all, so no tool could
place anything; the drawn grid and every overlay (statistics card, legend,
empty-plan hint) were positioned against the whole canvas instead of the fitted
plan rectangle, so they covered empty space and ran off the window; and the
restored window frame was taller than the display, cutting the bottom of the
plan away. Clicks now arrive through a `DragGesture` with a movement threshold
in the sheet's own coordinates, the sheet owns its frame for drawing and
overlays, `Views/WindowLayout.swift` fits the window into `visibleFrame`, and
the four tool booleans became `Models/SurveyToolMode.swift` so two tools can no
longer fight over one click. Heat cells fade with the distance to the nearest
sample, which stops a single measurement from colouring the whole floor.

## Delivered in the forty-first slice (2026-11-20)

- **Hierarchical tables sort from their headers.** `AppTable` learned
  `AppTableGrouping`: a group row starts a section, the sorter orders sections
  by their header value and sorts each section's children among themselves, so
  expanding a group and sorting a column do not interleave unrelated rows.
  Columns can opt out of sorting (`isSortable: false`) and `onActivate` handles
  a whole-row click, which is how a group expands. Connections and Process
  Traffic moved to it, `TableSortControl` is deleted, and every SwiftUI table in
  the app now sorts from its header. No screen is left on the native `Table`.

- **Offline Capture sorts from its headers.** The beacon table and both sheet
  tables (captured clients, management-frame counters) use `AppTable`. The
  three local sort enums, their comparators and the `TableSortControl` menus
  are gone, so a column's title, the value it sorts by and the cell it draws
  come from one declaration. The obsolete multi-column comment about native
  tables in WARP.md now lists only the hierarchical Connections screens.
- **Every non-hierarchical SwiftUI table in the app is on `AppTable`;** the
  remaining native `Table` views are Connections and Process Traffic.

## Delivered in the fortieth slice (2026-11-19)

- **Header sorting, batch 2:** Speed Test history, Roaming, DNS Propagation,
  Device Shelf, Client Analytics (AP load and captured clients), Controllers,
  Remote Sensors, Live Client Discovery and LAN Scanner. `AppTable` selection
  and per-row menus carried the interactive cases; LAN Scanner reuses
  `LANSort` for both the header and the values.
- **Overview:** gateway, its MAC and the DNS verdict are outside the Wi-Fi
  branch, so they stay visible on Ethernet; metric tiles do not repeat them.
- **Remaining:** none in this area — with the hierarchical sorter in place every
  SwiftUI table in the app sorts from its header.
- 635 tests green (1 skipped), lint clean, Debug and universal builds succeed.

## Delivered in the thirty-ninth slice (2026-11-19)

- **Project sources are folder-based.** `project.yml` lost the
  `SharedToolchainSources` template and the test target's per-file list; app,
  CLI and tests now share `Models`, `Services`, `Utils` and `CLI` as folders.
  Adding `DNSBenchmarkService.swift` no longer needs any project edit — the
  exact problem that started this thread. Verified by building `lanfi-cli` and
  running the 635-test suite from the same sources.
- **Header sorting on five more screens:** Port Scan TCP/UDP, HTTP Traffic,
  iperf3 history, Uptime checks, Network Monitor routes. `AppTable` now supports
  row selection and a per-row context menu, so interactive tables no longer
  need SwiftUI's `Table`.
- **Still on native `Table`:** Connections / Process Traffic (hierarchical,
  expandable rows), LAN Scanner (custom `LANSort` column model), Speed Test
  history, Roaming, Client Analytics, DNS Propagation, Device Shelf, Offline
  Capture, Remote Sensors, Controllers and Live Client Discovery. These are the
  next slice; the Wi-Fi analyzer keeps its own sort/filter UI by design.
- 635 app tests green (1 skipped); lint, Debug build and `./build.sh` succeed.

## Delivered in the thirty-eighth slice (2026-11-19)

- **P3.7 / P3.4 review.** The duplicated timer, in-flight guard, published
  sampling flags and event posting moved into `PollingGuard` and
  `SecurityEvent`; the duplicated `Process` wrapper became `ShellOutput.run`,
  and `RouteTableOutput` now asks `TunnelInterface` instead of repeating the
  prefix list. Eighteen guard/network localization keys that no Swift code
  referenced (old `%1$@` variants and the superseded DNS lines) were removed
  from all five locales.
- **P3.9 crash-proof launch.** `TerminalLauncher.open` is `async` and waits for
  `osascript` in a detached task, so the first Automation consent sheet cannot
  freeze the window; both call sites surface a refusal, including the LAN
  Scanner context menu, which had swallowed the result.
- **Overview without the main window.** `NetworkToolkitView` and
  `OverviewDashboardView` take the meter explicitly, defaulting to the shared
  `MenuBarMeterModel`, so previews and the snapshot harness do not need the
  app's environment objects.
- **Overview redesigned.** Link and internet lead, four equal tiles follow,
  then live throughput / uptime, bands / channels, and a uniform quick-action
  grid; gateway, DNS and MAC sit under the connection. Buttons fill their grid
  cells instead of sizing to their labels.
- 635 app tests green (1 skipped); lint clean, Debug build and `./build.sh`
  succeed.

## Delivered in the thirty-seventh slice (2026-11-19)

- **Header sorting on four more tables.** Whois events, Path Check ports, the
  TLS chain and DNS answers use `AppTable`; their `TableSortControl` menus and
  local sort state are gone. The Wi-Fi analyzer keeps its own sort/filter UI by
  design; the remaining `Table` screens are listed in WARP.md.
- **Whois + GeoIP merged.** One screen, one target mirrored between the tabs,
  one sidebar row (`Whois & GeoIP`); the GeoIP row stays as a hidden deep link.
- **MTR folded into Traceroute.** The Route tab keeps the map and hop table and
  MTR is the Continuous tab; the dead `TracerouteToolView` and the
  `ToolScreen.traceroute` route were removed, and `ToolRoutingTests` now cover
  both merges.
- **Dead survey code removed.** `heatGridRequestKey` was written and never
  read; the old heatmap request stream is gone entirely (the grid is built once
  per request key in a detached task).
- **P4.6–P4.9 dropped from the plan** at the maintainer's request: per-tool
  history, quick-control surfaces, import dry-run and accent personalization are
  no longer planned work.
- **project.yml de-duplicated.** `DiagnosticsHistoryStore.swift` and
  `UptimeStore.swift` were listed twice in the shared template; the template is
  the single list the CLI and the test target inherit.
- 635 app tests green (1 skipped, 2 new routing tests); lint and Debug build
  clean.

## Delivered in the thirty-seventh slice (2026-11-20)

- **Copy follows the DNS screen.** With a resolver comparison open, Copy now
  writes the comparison (`DNSComparison.exportText`: one row per resolver with
  transport, answer, time and failures marked, then the verdict and the failed
  count) instead of the stale single-lookup answer, and Copy/Clear stay enabled
  because `hasResult` counts the comparison. The export text lives in the model
  so it is unit-tested.
- **Dashboard cards are the navigation target.** `dashboardLink(_:)` wraps a
  card in a whole-card hit area with a hover outline; connection, internet, the
  four metric tiles, throughput, uptime, band and channel cards and the link
  automation card all open their tool (or the matching Settings page) from
  anywhere in the card, not only from the button in the corner.
- **Tables fill their card again.** `AppTable` measures its container and gives
  the content a `minWidth` floor, so rows stretch across the card (the previous
  `ScrollView` proposed nil width and every table collapsed to its intrinsic
  size) while horizontal scrolling still appears when columns need more room.
- 679 app tests green (1 skipped); lint and the universal bundle clean.

## Delivered in the thirty-sixth slice (2026-11-19)

- **Dashboard first (D2/P1.6 precursor).** `ToolboxTool.overview` is the new
  first entry and the default selection: `Views/Toolkit/OverviewDashboardView.swift`
  pairs the connected network with internet reachability, gateway/DNS, VPN and
  leaks, today's traffic, band distribution, the busiest channels, a throughput
  sparkline, uptime targets and quick actions. The analyzer moved from "the
  app" to one card and one sidebar row; the dashboard reads the shared services
  (`ConnectivityWatchdog`, `GatewayGuard`, `VPNGuard`, `TrafficAccounting`,
  `MenuBarMeterModel`, `UptimeMonitor`, `LinkAutomation`) so nothing is polled
  twice.
- **Interval menu stabilised.** The countdown is a button plus popover instead
  of a native `Menu`: opening it freezes the 0.5 s `TimelineView`, the label is
  whole seconds in a fixed-width slot, and a chevron with a hover tint restores
  the click affordance the hidden menu indicator removed.
- **Notification permission with link automation.** Turning the automation on
  requests authorization once; a refusal shows an inline warning and a button to
  Notification settings, so Wi-Fi switches can no longer fail silently.
- 633 app tests green (1 skipped); lint and Debug build clean.

## Delivered in the thirty-fifth slice (2026-11-19)

- **Toolkit control unification (D5).** The remaining raw `Button` calls on the
  tool screens were migrated to `AppButton`/`AppIconButton` — DNS (run and
  resolver benchmark), LAN Scanner (permission gate), GeoIP, Internet Check,
  Client Analytics, iperf3, Known Networks, Roaming, Uptime, Connections,
  Process Traffic, Connection Rules and Coming Soon, plus the export, refresh,
  "check now", inspector and expand/collapse actions on HTTP Traffic, Network
  Monitor, Security Watch, Advanced Tools, Known Networks and the LAN Scanner.
  The LAN Scanner and Known Networks header strips now use `ToolkitHeaderBar`
  instead of their own padded `HStack` + `Divider`. Menus, context menus and
  confirmation dialogs keep native buttons by design; row-level destructive
  icons stay native because the kit has no destructive tone yet.
- **DMG packaging.** The image is a drag-to-install folder (app, Applications
  alias, bilingual read-me pages with the Gatekeeper steps for an unsigned
  build) built from a read-write image with an AppleScript layout.
- **Signal/quality bar geometry.** `SignalBarMetrics` owns the arithmetic and
  the table cell measures text explicitly; five tests cover narrow and wide
  columns.
- **AppTable simplification.** Columns take a `@ViewBuilder` cell instead of a
  hand-written `AnyView`; `NetworkComparisonTable` uses it, so the comparison
  table no longer builds 13 closures by hand.
- 633 app tests green (1 skipped); lint and Debug build clean.

## Delivered in the thirty-fourth slice (2026-11-19)

- **Privacy policy and settings.** New Settings → Privacy page with the policy,
  the never-collected list and an off-by-default anonymous statistics switch;
  `PRIVACY.md` is the long form. Settings → Toolkit manages the shared analysis
  target and its recent list.
- **Help screenshots removed.** Topic pages draw a symbol banner instead of a
  bundled screenshot, so the manual cannot leak SSIDs, BSSIDs, addresses or
  device names.
- **Table sorting by column header.** `AppTable` (comparison, visual traceroute,
  DNS benchmark, Ping probes, MTR hops) now sorts from the header; those screens
  no longer carry a separate sort menu. Remaining SwiftUI `Table` screens are
  listed in WARP.md as the follow-up.

## Delivered in the thirty-third slice (2026-11-19)

- **The shared target history records every run.** History was only written by
  the field's Return key, so pressing Ping / Trace / Start never stored the
  address; every probe model now remembers its target when it runs, and the
  field's history control carries a visible "Recent" label instead of a bare
  clock glyph.
- **MTR draws its hop chart.** The Swift Charts view rendered an empty card; the
  plot is now a `Canvas` that draws average latency as a line, packet loss as
  bars on the same hop axis, with ms labels and a legend, so it renders whenever
  there is at least one hop.
- **Site Survey taps work again.** The plan used the deprecated
  `onTapGesture` location closure, which no longer delivered coordinates, so
  samples, walls, rooms, access points and calibration could not be placed —
  and without samples the heatmap never had anything to interpolate. The plan
  now uses `SpatialTapGesture`, the heat grid is built once per request key on a
  background task, and a "Computing coverage…" note makes the wait visible.
- **P3.5 task 1 — resolver benchmark.** A card on the DNS screen measures the
  median lookup time of three names, three rounds each, through the system,
  Cloudflare, Google and Quad9 resolvers, ranks them and names the fastest one
  that answered everything. Read-only: no switching, no admin prompt.
  `Models/DNSBenchmark.swift`, `Services/DNSBenchmarkService.swift`,
  `ViewModels/Toolkit/DNSBenchmarkModel.swift`, `Tests/DNSBenchmarkTests.swift`.

## Delivered in the thirty-second slice (2026-11-19)

- **Minimum window that fits the whole UI.** `DesignToken.Layout` now carries
  one `windowMinWidth`/`windowMinHeight` (1160 × 700) used by the app window and
  the toolkit, instead of the old 980–1000 × 640 frames that clipped the toolbar
  and the inspector.
- **LAN Scanner names.** PTR names discovered by the scan were merged into the
  Bonjour advertisement but never handed to the assembler, so the Device and
  Hostname columns stayed empty on networks that do return names; they are now
  passed as `hostnames:`.
- **Devices tab order.** The All / In network / Favourites filter now sits above
  the search field, where the coarser choice belongs.
- **Traceroute merged into Visual Traceroute.** The map screen gained the
  classic screen's controls (probes, timeout, resolve names) and a sortable hop
  table built on `AppTable`; the separate Traceroute entry is now a hidden alias
  of the same screen, so the sidebar no longer offers two near-identical tools.

## Delivered in the thirty-first slice (2026-11-19)

- **One control kit (UI unification).** New `Views/AppControls.swift` holds the
  single button (`AppButton`/`AppIconButton`), list row (`AppListRow`), search
  field (`AppSearchField`) and toolkit header strip (`ToolkitHeaderBar`).
  Connections and Network Monitor now share the same tab strip and header
  chrome instead of a segmented `Picker` versus a custom `HStack`; the toolkit
  sidebar tool list, its search field, its detail header, the toolkit sort menu
  and `ToolbarIconButton` all route through those components.
- **P3.6 step one (per-app traffic history).** `AppTrafficHistory` keeps hourly
  per-app byte buckets for seven days in `app-traffic-history.json`, sampled
  every five minutes from the same `nettop` deltas while Process Traffic is on,
  excluding LanFi's own process. The Process Traffic screen gained an "App
  history" card with today's total, the top apps and CSV export. Domains and
  full URLs are still not attributed — that half of P3.6 remains open.

## Delivered in the thirtieth slice (2026-11-19)

- **Traffic accounting (P2).** `TrafficAccounting` reads the same interface
  byte counters the throughput sampler uses once a minute, folds the deltas
  into per-day and per-interface buckets, and keeps the ledger in
  `traffic-accounting.json`. The Network Monitor overview gained a Data usage
  card with today, last 7 days, this month and lifetime totals, a Reset button
  and CSV export. Days are keyed in the user's calendar; old days prune after
  400 days while the lifetime total is never reduced. The same slice also
  unified the analyzer's dropdowns (`AppMenuLabel`), made the scan-interface
  caption a working menu, let the signal/quality bars fill their column, and
  rebuilt the comparison table on the shared `AppTable` + `TableSorter`.

## Delivered in the twenty-ninth slice (2026-11-19)

- **P3.8 Wired/Wi-Fi link automation.** The analyzer's countdown pill is now a
  menu. Separately, `LinkAutomation` polls the hardware ports every 10 s and,
  when the user opts in (off by default), turns Wi-Fi off once when a physical
  Ethernet link comes up and back on once when it goes away. It is strictly
  edge-triggered: a manual Wi-Fi change wins, a manual disable while docked
  survives a re-plug, VPN/VM/bridge devices are never treated as an uplink, and
  a master pause stops all writes. Each change posts a notification, and the
  Settings card shows the wired interface, Wi-Fi power and the last action.

## Delivered in the twenty-eighth slice (2026-11-19)

- **P3.4 VPN status and leak indicators.** `VPNGuard` polls the local route
  tables and `scutil --dns` every 20 seconds: a tunnel is detected from the
  default route or an up `utun`/`ipsec`/`ppp` interface, a DNS indicator reports
  when the resolver in use is not one the tunnel pushed, and an IPv6 indicator
  reports a global IPv6 default route leaving through a non-tunnel interface.
  Both are worded as indicators, not proof. An unexpected tunnel drop and a new
  leak raise `VPN dropped` / `Possible VPN leak` Monitor events with their own
  alert toggles, the Security Watch screen gained a "VPN and leaks" card with
  the tunnel, DNS and IPv6 state, and the guard is on by default with a switch
  in Settings → General. No provider API is queried and no credential is read.

## Delivered in the twenty-seventh slice (2026-11-19)

- **P3.7 gateway ARP and DNS-hijack detection.** `GatewayGuard` re-reads the
  default gateway and its ARP entry every two minutes and posts a critical
  `Gateway MAC changed` Monitor event when the address changes while the IP
  stays the same; a hidden ARP table (Local Network access off) is treated as
  unknown, never as a spoof. Every ten minutes it also compares the system
  resolver's answer for `captive.apple.com` with Cloudflare's direct answer and
  raises a warning-level `DNS answer mismatch`. Both events flow through the
  existing Monitor log, quiet hours, cooldown and per-kind toggles, and the
  Security Watch screen gained a Gateway/DNS integrity card plus matching
  alert rows. The guard is on by default and can be turned off in Settings.

## Delivered in the twenty-sixth slice (2026-11-19)

- **P3.10 plain-language service descriptions.** Connections gained a Service
  column and the HTTP traffic screen a Service column plus an inspector row:
  `gateway.icloud.com` reads "Apple push notifications",
  `com.apple.WebKit.Networking` reads "Web content hosted by an app", and an
  unlisted name reads "Unknown service" with the raw identifier a copy away.
  The bundled catalogue is offline and exact-before-suffix, so it works on
  macOS 13; on macOS 26 the opt-in on-device model can label unknown hosts
  locally, and the toggle only appears when Apple Intelligence is ready. 7 pure
  tests cover matching and normalization.

## Delivered in the twenty-fifth slice (2026-11-19)

- **P3.9 SSH quick launch.** Saved sensors have "Open in Terminal" and "Copy SSH
  command" on the sidebar row, and the detail header gained a Terminal button;
  a LAN Scanner device whose scan found port 22 open offers "Open SSH session"
  in its context menu. `SSHLaunchCommand` quotes the destination, port and key
  path for the shell (`O'Brien` → `'O'\''Brien'`), and the Terminal hand-off
  escapes the AppleScript literal again, so a hostname cannot break out of the
  command. Nothing is read from the Keychain, no password is typed and no key is
  generated.

## Delivered in the twenty-fourth slice (2026-11-19)

- **P3.1 listener watch.** Connections now lists UDP sockets next to TCP ones
  (Proto carries the transport), every row gains an **Exposure** column built
  from the local endpoint — loopback, all interfaces or one specific address —
  and the summary counts LAN-reachable sockets separately. A persisted "Watch
  listeners" toggle samples `lsof` every 30 s, diffs the set by PID + transport
  + endpoint and posts one notification per new or closed listener through the
  shared notifier; the first sample is a baseline, so turning it on does not
  announce every server already running. 8 pure tests cover UDP parsing,
  exposure classification, the diff and the notification copy.
- **No "public" claim.** Sockets are labelled "LAN-reachable", and the card
  says why: without a router table LanFi cannot know whether a port is
  forwarded.

## Delivered in the twenty-third slice (2026-11-19)

- **P3.3 connectivity watchdog.** The menu bar now answers "is the internet
  working right now?" instead of only echoing the last diagnostics run. A
  `NWPathMonitor` plus a timed probe (`http://captive.apple.com/hotspot-detect.html`
  with a configurable fallback) produce an online / captive-portal / offline
  verdict; a redirect or a portal page is labelled as a portal, not as offline,
  and one failed probe never flips a healthy link. Transition notifications
  reuse the Monitor quiet hours with per-direction toggles and a cooldown, the
  label icon turns into `wifi.slash` when the WAN is dead, and the latency
  metric reads the watchdog's live sample. Settings → General gained the
  watchdog card (interval, probe URLs, toggles), and the state is exposed to
  Shortcuts. 13 pure tests cover the machine, classifier, policy and settings.
- **One notification delegate.** `MonitorNotifier` is now the single shared
  `UNUserNotificationCenter` delegate, with a generic `post` used by the
  watchdog; the monitor reuses the shared instance instead of installing a
  second delegate.

## Delivered in the twenty-second slice (2026-11-17)

- **LAN Scanner header no longer disappears.** The Devices tab's shelf asked
  for unbounded height (header card + table + inspector), so the VStack
  overflowed and the tool header was clipped off-screen. The shelf now scrolls
  and its table has a computed height.
- **One Connections tool.** Open Connections and Process Traffic answer the same
  question from two sides, so they share one sidebar entry with Sockets / Traffic
  tabs (`ConnectionsToolView`). `processTraffic` stays routable for deep links but
  is `showsInSidebar: false` in the registry.
- **Working sorting in toolkit tables.** macOS 13 has no sortable
  `TableColumn` (`value:`/comparator initialisers are macOS 14), so tables sort
  through `TableSortControl` in the card header: LAN Scanner devices, Device
  Shelf, Connections sockets and Connections traffic expose every meaningful
  column. The remaining toolkit tables need the same three-line pattern.
- **MCP straight from the app.** `LanFi.app/Contents/MacOS/LanFi --mcp` serves
  the protocol on stdio and never starts AppKit, so
  `claude mcp add lanfi -- /Applications/LanFi.app/Contents/MacOS/LanFi --mcp`
  works without a separate CLI binary.
- **Survey scale fix.** The predictive heatmap used a 30 m fallback while the
  grid and `fittedRect` used 12 m, so predicted coverage was computed at the
  wrong scale; the view now resolves `planWidthMeters` once for all three.

## Delivered in the twenty-first slice (2026-11-17)

- **P0.5 decoder depth: RSN Override.** Vendor IEs with the Wi-Fi Alliance OUI
  `50-6F-9A` are now named and decoded: RSNE Override and RSNE Override 2
  (`0x29`/`0x2A`) reuse the RSNE parser because their payload is the RSNE
  Information field, so a Wi-Fi 7 compatibility-mode AP is no longer reported as
  "WPA2-PSK only" with no trace of its SAE/AKM-24 advertisement; Hotspot 2.0
  (`0x10`) and SAE-PK (`0x1F`) are named instead of "Vendor Specific". The
  security protocol block gains an "RSN override" fact, so the mode is visible
  without opening the raw IE list. Tests cover the override payload, the
  truncated fallback and the named elements.
- **Gap doc truth pass.** The P1 tool list still showed Security Watch, Roaming
  Test, Client Analytics, Survey Planning, Active Survey, Combined Report,
  Shortcuts, Known Networks, Connections and Per-process traffic as unstarted
  long after they shipped; each is now marked done or partial with the concrete
  remainder named.

## Delivered in the twentieth slice (2026-11-17)

- **Palette, reviewed and wired.** `AccessibilityPalette` resolves ten roles to
  five Okabe–Ito hues through one switch and caches the on/off flag, so the
  table no longer hits `UserDefaults` per cell. The unused
  `lanfiColorBlindSafe` environment key is gone: the Settings toggle writes the
  cache and the main window rebuilds on the flag, which is what actually
  repaints every `AppPalette` leaf without a relaunch.
- **Snapshot harness and script (D8).** `ToolkitSnapshot` shares one
  `capture`/`writePNG` path for the survey, map and settings screens instead of
  three near-identical blocks, and drops the debug flags nothing referenced
  (`--host`, `--settings`, `--udp`, `--dns-tab`, `--uptime-demo`).
  `scripts/visual-check.sh` drives the toolkit captures from one
  `file:tool` table for both themes.
- **D7 slice.** Reduce motion now guards every animation in the app, and the
  inspector/protocol surfaces got combined VoiceOver stops and explicit labels.
- **MCP catalogue docs.** `docs/mcp.md` lists `lanfi_har`,
  `lanfi_client_analytics`, `lanfi_survey_plan` and `lanfi_open_connections`
  with their arguments and call examples; the table now matches
  `MCPToolkit.definitions` exactly.

## Delivered in the nineteenth slice (2026-11-17)

- **Per-network speed-test history (P2).** Every `networkQuality` run records
  the connected SSID/BSSID through `ThroughputNetworkSampler`, and
  `SpeedTestHistoryIndex` groups tests by SSID, newest first, with latest,
  previous, average download/upload and signed deltas. The History tab gains a
  network picker, a summary card (latest down/up, latency delta, average,
  bufferbloat grade) and a Network column; tests recorded before this change
  still decode and stay in the All view as "Not recorded".
- **Store compatibility.** `ThroughputMeasurement.network` is optional and
  optional in synthesized `Codable`, so existing `speed-tests.json` files need
  no migration.
- 501 app tests green (4 new); lint clean; Debug build passes.

## Delivered in the eighteenth slice (2026-11-17)

- **D5 — toolbar and menu-bar chrome.** `ToolbarIconButton` and the
  `appToolbarChrome` modifier give the Wi-Fi workspace and the toolkit header
  one control height, radius, stroke and icon+label rule. The refresh/pause,
  settings, export, inspector, diagnostics, location and Help controls are
  migrated; the menu-bar label renders monochrome as a template image.
- **Sparkline geometry.** The menu-bar sparkline is now drawn from the pure
  `SparklineGeometry` and the `ChartStyle` sparkline tokens (1.5 pt stroke,
  shared fill/baseline opacity), covered by 8 geometry tests for empty, flat,
  single-value, clamped and evenly spaced input.
- **Icon audit (D5).** Icon-only controls in the chart toolbars, filter bar,
  spectrum/history zoom, device shelf, remote sensors, uptime, controllers and
  notification banner gained tooltips and accessibility labels. `ToolkitTone`
  and `ToolkitStateDot` now use `AppPalette`, so the `Planned` badge follows the
  colour-blind-safe palette too.
- **Wi-Fi card selection (P2).** The workspace toolbar shows
  "Scanning with <interface>" next to the scan controls; `WiFiInterfaceCatalog`
  resolves the Settings choice or the system default, matching `WiFiScanner`.
- 497 app tests green; lint clean; Debug build and the visual-check screenshot
  set pass.

## Delivered in the seventeenth slice (2026-11-17)

- **P0.5 decoder depth.** Extended BSS Load (IE 193) now exposes MU-MIMO STA
  count, spatial-stream underutilization and secondary 20/40/80 MHz utilization;
  Multiple BSSID (IE 71) lists non-transmitted profiles and their BSSID index.
  Covered by synthetic-byte tests.
- **P0.1 permission reset documentation.** `DISTRIBUTION.md` explains the
  TCC/code-signing identity link, the `identifiersHidden` diagnostic and the
  recovery steps, plus the signed-release checklist.
- 486 app tests green; lint and universal Release build pass.

## Delivered in the sixteenth slice (2026-11-17)

- **P1.6 MCP actions for the new tools.** The CLI catalogue now exposes
  `lanfi_client_analytics` (per-AP advertised load + insights from the live
  snapshot/export), `lanfi_survey_plan` (AP layout, radius, spacing, coverage
  and notes) and `lanfi_open_connections` (read-only lsof rows, listeners,
  limit, per-process summary). Definitions, handlers and catalogue tests are
  updated; the CLI target compiles the shared models.
- **D7 accessibility slice (partial).** Shared `ToolkitStatusPill`,
  `ToolkitMetric` and `AppTabBar` now expose combined labels/values; Survey's
  icon-only floor/structure/clear controls and the GPX map have explicit
  VoiceOver labels and a map value (track points, tagged samples). Full
  colour-blind palette, Dynamic Type and a hands-on VoiceOver pass remain open.
- 481 app tests green; CLI target builds; lint clean; universal Release build
  passes.

## Delivered in the fifteenth slice (2026-11-17)

- **P1.8 Open connections.** `OpenConnectionsParser` reads the fixed `lsof`
  column layout into process/PID/user/protocol/endpoints/state rows;
  `OpenConnectionsService` runs `/usr/sbin/lsof -nP -iTCP` read-only (never a
  shell, never elevated). The Network Tools screen adds filtering, listening
  sockets, per-process summary and copy. Tested against established, listening,
  IPv6 and malformed rows.
- **GPX route drawing.** Survey map now draws a real polyline via an `MKMapView`
  bridge, with sample markers, current location, bundled demo walk and GPX
  import/export. Verified visually (`screenshots/survey-map.png`).
- **Design unification.** Expanded `DesignToken.Spacing` (compact/card/sheet/
  empty-state) and `Radius` (tiny/badge/control/card/sheet); migrated 61 view
  files off literal paddings and radii, and table column literals to
  `AppColumnWidth`. Sheets/tables use `appSheet`, `appSheetHeader`,
  `appTableSurface` and `ToolkitTableHeight`.
- **Review fixes.** Planner clamps zero/negative dimensions; GPX map signature
  covers mid-track changes; location delegate hops to main explicitly; login
  item status refreshes on appear; test fixture simplified.
- 479 app tests green; lint clean; universal Release build passes.

## Delivered in the fourteenth slice (2026-11-16)

- **Settings, finished.** General settings moved to card-based sections on the
  shared spacing tokens: about/version, appearance (theme, live row density,
  high contrast), startup (login item via `SMAppService`, scan on launch,
  refresh interval), updates (Sparkle auto-check, last check, release page,
  Homebrew), menu-bar meter, display/toolbar, data/privacy and help. The old
  single `Form` implementation was deleted.
- **P1.3 Client analytics.** `ClientAnalyticsSnapshot` merges beacon client
  counts with captured client observations (unique MACs, frames, vendor mix,
  probe SSIDs, average RSSI) and emits insights; the new Wi-Fi tool shows the
  AP load table and an optional 10 s monitor capture. Tested.
- **P1.9 GPS map.** `GPXCodec` parses/writes GPX 1.1; samples gained optional
  latitude/longitude and projects an optional track. The MapKit sheet plots the
  walk and samples, imports/exports GPX and tags the newest sample with the
  current location. Tested parsing, round-trip and distance.
- **P1.4 Survey Planning 2.0 + Active Survey.** `SurveyPlanner` derives a
  free-space radius from tx power/target and returns a grid AP layout with a
  coverage estimate; `ActiveSurveyAdvisor` reports required samples, covered
  cells, gaps, next target and weakest/average RSSI. The Plan sheet applies the
  layout to the project and tracks the walk-through. Tested.
- **Reuse.** `appSheet`, `AppSheetHeader`, `AppColumnWidth`, `appTableSurface`
  and the expanded `DesignToken.Layout` are used by all new screens; LAN Scanner
  and planning use `AppTabBar`; sheets and table columns no longer invent their
  own widths.
- 476 app tests green; lint clean; universal Release build passes.

## Delivered in the thirteenth slice (2026-11-16)

- **One density, live.** `Views/TableStyle.swift` adds an app-wide
  `appTableDensity()` modifier that reads `LanFi.rowDensity` through
  `@AppStorage` and injects `appTableDensity`, `defaultMinListRowHeight` and a
  matching `controlSize`. It is applied at the toolkit root and in Settings, so
  Compact/Standard/Roomy changes lists, tables and row controls without a
  relaunch; the AppKit Wi-Fi table already reloads on the same key.
- **One tab strip.** `Views/AppTabBar.swift` is the shared tab component; the
  Wi-Fi workspace's bottom strip now builds on its sections/items, replacing the
  private `TabButton`/`TabGroup` duplicates. Inside the toolkit every split
  screen uses it through `ToolkitHeaderBar` — DNS Lookup/Propagation, Whois &
  GeoIP, Visual Traceroute, Connections and Network Monitor — and the strip has
  a fixed row height so trailing captions and buttons cannot change its size.
- **Known Networks master/detail.** Rows are selectable and open a detail pane
  with saved-name state, live band/channel/width/security/BSSID/signal/quality,
  or a clear "not in range" explanation, plus the guest QR action. The QR sheet
  was rebuilt with a fixed 220 pt code, explicit field widths and a 620 pt
  minimum window so the code and payload no longer clip.
- **Survey blank plans.** `New Plan…` (toolbar and onboarding) creates an
  image-less plan from real metre dimensions (`planHeightMeters` added as an
  optional, backward-compatible field). The canvas draws a labelled metre grid,
  keeps the correct aspect ratio, and supports the existing wall/room/sample/AP
  tools; onboarding and the step-by-step hints mention the blank-plan path.
- **Bars follow their column.** The signal/quality bar width is now derived from
  the live `NSTableColumn.width` (28–72 pt) and bar cells left-align the number
  immediately after the bar, removing the gap in wide columns.
- 467 app tests green; lint clean; universal Release build passes.

## Delivered in the twelfth slice (2026-11-16)

- **P1.1 Security Watch (MVP).** A new Wi-Fi tool evaluates the live scan for
  twin and downgrade signatures and shows captured deauth bursts:
  - evil twin: one BSSID of an SSID is open or WEP while another BSSID of the
    same SSID is WPA2/WPA3 or better, excluding radios the co-location detector
    proved belong to one chassis;
  - security downgrade: the same mix with legacy WPA, while routine WPA2/WPA3
    band mismatches stay quiet;
  - randomized BSSID: a locally administered address broadcasting an SSID that
    also appears from registered hardware addresses;
  - live deauth: `.deauthBurst` monitor events from packet captures within the
    last 15 minutes, with an "Open Capture" action and an explicit note that
    macOS gives apps no passive deauth feed.
- `SecurityWatchEvaluator` is pure and tested; the screen is read-only (no
  framing, injection or deauthentication) and links a suspect BSSID back to the
  analyzer selection.
- 466 app tests green (8 new); lint clean; universal Release build passes.

## Delivered in the eleventh slice (2026-11-16)

- **D4 — one chart language.** `ChartStyle` now reaches every chart surface:
  the Canvas spectrum takes its grid colour/dash, axis labels, lane dividers,
  hover cursor line and tooltip surface from the tokens, and the Uptime and Ping
  latency charts share one Swift Charts `AxisMarks` definition instead of
  stock axes.
- **D4 — inspector restructure.** The Link block is pinned above the scrolling
  inspector sections (it no longer scrolls away) and now includes cipher and
  BSSID alongside rate, PHY, width, band/channel, streams, noise and the
  rate min/avg/max summary.
- **D2 — menu-bar open target.** "Open LanFi" from the menu-bar popover now
  selects the Wi-Fi workspace on bottom tab 9, so the all-band RF overview is
  the first surface, without changing stored user layouts.
- **P0.5 — 6 GHz power mode.** `SixGHzOperationInfo` decodes the HE Operation
  element's 6 GHz Operation Information (primary channel, width, duplicate
  beacon, regulatory info, CCFS0/1, minimum rate) and maps regulatory info to
  LPI / SP / VLP. The inspector's Regulatory section and the raw IE view show it;
  this is a beacon decode, not a CoreWLAN capability.
- **P0.5 — RNR.** `ReducedNeighborReport` decodes element 201: TBTT header,
  operating class, channel, TBTT offset, BSSID, short SSID, BSS parameters,
  20 MHz PSD and MLD parameters, and `InformationElementParser` lists each
  neighbour with its band and marks 6 GHz entries.
- 458 app tests green (8 new); lint clean; universal Release build passes.

## Delivered in the tenth slice (2026-11-16)

- **Roaming Test** (`Models/RoamingTest.swift`, `Views/Toolkit/RoamingTestToolView.swift`):
  advertises 802.11k (IE 70), 802.11v (IE 54) and 802.11r for the connected
  BSSID, derives BSSID transitions and failed roams from the monitor samples,
  and raises sticky-client (≤ −75 dBm with a sibling +10 dB stronger) and
  band-steering (2.4 GHz with a 5/6 GHz radio +6 dB stronger) verdicts. A walk
  test narrows the window to the last "Start Walk Test" click.
- **Known Networks + Wi-Fi QR** (`Models/KnownNetwork.swift`,
  `Services/KnownNetworksService.swift`): reads the preferred-network names with
  the public `networksetup -listpreferredwirelessnetworks` (names only, no
  passwords, no Keychain), marks which are in range, and builds a guest
  `WIFI:` QR payload from a user-typed password.
- **App Intents / Shortcuts** (`Services/LanFiIntents.swift`): scan summary,
  connected-network summary and speed test, plus `LanFiAppShortcuts` phrases.
  MCP keeps its existing catalogue (scan analysis, monitor, speed test) — no new
  MCP actions in this slice.
- **Connected-link telemetry** (`Models/LinkTelemetry.swift`,
  `ViewModels/ConnectedLinkMonitor.swift`, `Views/WiFiWorkspace/LinkInspectorSection.swift`):
  a 5 s sample of transmit rate, channel, width and noise, min/avg/max over the
  last 60 samples, plus PHY and beacon NSS capability labelled as capability —
  CoreWLAN exposes neither MCS nor live NSS.
- **Combined report** (`Models/CombinedReport.swift`,
  `Services/CombinedReportExporter.swift`, `Data → Export Combined Report…`):
  one self-contained HTML file with scan rows and quality, survey summary,
  security findings, diagnostics, recent speed tests and monitor events.
- **Settings sidebar** (D6): grouped `NavigationSplitView` over the existing
  settings screens, last section persisted.
- 450 app tests green (16 new); lint clean; universal Release build passes.

## Delivered in the ninth slice (2026-11-16)

- History chart mode switch (signal / noise / both) driven by
  `HistoryChartMode`; noise is drawn dashed from the samples `NetworkHistory`
  already kept, and percent mode stays signal-only.
- Shared `ChartStyle` tokens for axis labels, grid, cursor and tooltip; the
  history and occupancy charts use them.
- Visibility advice for 6 GHz PSC/non-PSC, DFS and hidden SSIDs, in the
  inspector and in the empty workspace.
- Co-located radio siblings are listed in the inspector and can be selected.
- SSID overhead (% of airtime) in the inspector's technical specs.
- First-run screen and the full placeholder matrix (no scan, no networks, no
  permission, no Wi-Fi hardware, failed scan, stale data, over-filtering) via
  the pure `WorkspacePlaceholderEvaluator`.

## Delivered in the eighth slice (2026-11-16)

- All-band RF overview as bottom tab 9 "All Bands": three band panels with
  physical MHz spans, overlap shading, recommended-channel marker,
  click-to-select, per-band footer and a shared legend. Geometry lives in the
  pure `RFOverviewLayout` with 10 new tests (frequency math per band, overlap,
  clamping, markers, busiest channel).
- Design tokens and shared components (`Views/DesignSystem.swift`): spacing,
  radius, stroke and semantic palette plus `AppCard`, `SectionLabel`,
  `StatusPill`, `StatTile` and `BandChip`; the overview is their first consumer.
- Tab 9 is wired through the tab strip, the Layout menu (⌘9) and the panel
  router; fresh installs default to it and stored layouts are never rewritten.
- New strings ship in all five locales.
- 413 app tests green; lint clean; universal Release build passes.

## Delivered in the seventh slice (2026-11-15)

- Packet-indexed PCAP decoding: header-only index, on-demand packet slices, and
  the same summary/clients/security pipeline without an array of every packet.
- CSV/JSON shaping moved to pure exporters and encoded on a background task.
- Deauth-burst findings from offline/live capture analysis now become Monitor
  events with their own alert toggle.
- Roaming failures are detected when a BSSID transition lands on a much weaker
  link; alert toggle included.
- 385 app tests + 6 core tests green; universal Release build passes.

## Delivered in the sixth slice (2026-11-15)

- OUI lookup packed into an integer-key index; a regression test compares it
  with the string lookup for 24/28/36-bit prefixes.
- Heatmaps stream in chunks instead of waiting for the whole grid; detail
  selector is Fast/Balanced/High.
- Export encoding moved out of `AnalyzerViewModel` into testable exporters;
  file writing runs on a background task.
- 379 app tests + 6 core tests green; universal Release build passes.

## Delivered in the fifth slice (2026-11-15)

- Adaptive scan cadence: foreground uses the user interval, background slows to
  15 s and Low Power Mode to 30 s; a WiFi settings toggle can disable it.
- Survey heatmap no longer blocks the view: immutable request → detached grid
  build → published result; the key now invalidates on RSSI and wall/AP edits.
- `WiFiTableView` reloads only visible rows when the table structure is stable.
- PCAP files are memory-mapped instead of being copied into memory.
- OUI database warm-up moved to a background launch task.
- `MainTableView` split into six focused files; heatmap detail selector added.
- 375 app tests + 6 core tests green; universal Release build passes.

## Delivered in the fourth slice (2026-11-15)

- All-BSSID aggregates: every visible network now tracks min/max/avg RSSI,
  sample count, channel, security and last-seen time; a peer table and a
  separate networks CSV expose them.
- PMF loss and WPS-enabled transitions join the security event stream.
- Before/after comparison for 1 h / 6 h / 24 h with a signed dBm delta and
  sample counts.
- 366 app tests + 6 core tests green; universal Release build passes.

## Delivered in the third slice (2026-11-15)

- First SwiftPM module: `Packages/LanFiCore` with `AppSettings` and
  `AppSettingsStore` (defaults, legacy migration, export/import, write-through
  legacy keys) and 6 package tests.
- General Settings now edits typed `AppSettings`; export/import buttons write a
  portable JSON file.
- `ToolkitViewModel` split into 15 focused tool-model files.
- `ToolRegistry` centralizes tool title/icon/section/availability metadata.
- CI runs `swift test` for the core package and `swift-format` is blocking.
- 360 app tests + 6 core tests green; universal Release build passes.

## Delivered in the second slice (2026-11-15)

- Wi-Fi Monitor MVP in the bottom panel: connected-link sampling, retention
  picker, RSSI timeline, min/avg/max/p95, event log, CSV export and clear.
- Monitor alerts: per-kind toggles, quiet hours (including overnight), 0–60 min
  cooldown and an explicit macOS notification-permission request. 6 policy
  tests cover disabled kinds, quiet hours, overnight ranges and cooldown.
- Event detection for connect, disconnect, roaming, channel change, security
  downgrade and weak-signal crossing, with 10 unit tests.
- Monitor samples are throttled (15 s–15 min depending on retention) and
  persisted locally; the store trims by retention and caps samples/events.
- 358 tests green; lint clean; universal Release build passes.

## Delivered in the first slice (2026-11-15)

- OUI custom-override cache with write invalidation and a lock around both
  caches.
- Analyzer indexes networks by band and id instead of scanning the full list
  per network.
- Rolling history moved into `NetworkHistory`; one published update per scan.
- Signal and utilization inspectors show min/avg/max/p95.
- Grouping by advertised AP name (`Access point` mode).
- 342 tests green; lint clean; universal Release build passes.

## Delivery order

1. **Now (1–2 weeks):** P0.1 pipeline; P0.4 quick wins; P0.5 grouping and
   history stats; P0.3 MVP; **D1 tokens, D3 relative time and density**.
2. **Next (3–6 weeks):** P1.10 + D2 all-band overview and first run; P0.6
   menu-bar meter; P0.2 passive scan; P1 Security Watch and Roaming Test;
   combined report; Shortcuts/App Intents; MCP actions; **P3.3 connectivity
   watchdog and P3.1 listener watch** (small and menu-bar visible); D4–D6.
3. **Later (quarter):** P1.8 connections and per-process traffic; P1.9 GPS map;
   P2.6 link telemetry; P3.2, P3.4–P3.10; Survey Planning 2.0; spectrum hub;
   client analytics; sandbox/MAS split; BLE/Zigbee; 802.11bn readiness; D7–D8.

If the product stays a free home analyzer, stop after step 1 plus Security
Watch/Roaming. If it targets WiFi Explorer Pro, passive scan, history and
spectrum are required.

## Non-goals

- Ekahau-class predictive enterprise design and cloud planning. NetSpot 6
  multi-floor planning with antennas and floor materials is the prosumer bar,
  not a reason to build an enterprise RF planner.
- Cloud accounts, mandatory telemetry or a hosted dashboard.
- Windows/Linux ports before macOS signing and distribution are trustworthy.
- Packet-filter enforcement and content/ad blocking (LuLu, AdGuard). A network
  extension or root helper plus a TLS-intercepting proxy is a different trust
  surface; block rules keep terminating the owning process and say so.
- VPN clients and router-specific VPN peer management (Tunnelblick, Glinet
  Wireguard), network-share automounting (AutoMounter) and cross-device file
  transfer or KDE Connect features (Blip, Soduto).
- CI, commute and download managers from the same tag (Octowatch, TimeToGo,
  Transloader): they are not network tools.
- System posture audit for FileVault, SIP and Gatekeeper (Mojo Pulse): macOS
  already reports these, and only the network-layer hijack checks are planned
  (P3.7).

## Sources

- [Reference apps review, November 2026](REFERENCE_APPS_REVIEW_2026-11.md)
  (Unstore buyer's guide, NetWorker Pro, AirRadar 8, PeakHour 6)
- [On My Menubar network tag review, November 2026](ONMYMENUBAR_NETWORK_REVIEW_2026-11.md)
  (22 menu-bar listings, 12 relevant, 10 non-goals)
- [WiFi Explorer Pro 3](https://www.intuitibits.com/products/wifiexplorerpro3/),
  [documentation](https://docs.intuitibits.com/wifiexplorerpro3/),
  [release notes](https://www.intuitibits.com/release-notes/wifiexplorerpro3/)
- [NetSpot 6 multi-floor planning](https://www.netspotapp.com/help/netspot-6-0-with-multi-floor-planning/)
- [Airtool 2 release notes](https://www.intuitibits.com/release-notes/airtool2/),
  [packet captures](https://docs.intuitibits.com/airtool2/about-packet-captures)
- [macwifi: CoreWLAN, Developer ID and Location Services](https://pkg.go.dev/github.com/jaisonerick/macwifi-cli)
- [Apple forum: SSID missing since macOS 14.4](https://developer.apple.com/forums/thread/756344)
- [Apple forum: Local Network and child processes](https://developer.apple.com/forums/thread/856661)
- [ABI Research: Wi-Fi 8/802.11bn timeline](https://www.abiresearch.com/market-research/insight/7788568-wi-fi-8-presents-both-lucrative-opportunit)
