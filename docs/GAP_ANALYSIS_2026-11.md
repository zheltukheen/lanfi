# Gap analysis — November 2026

Status: **active plan**. Baseline: LanFi 5.2.0 (build 68).
Scope: post-Netutilus parity, compared with WiFi Explorer Pro 3.10, NetSpot 6,
Airtool 2 and the public macOS Wi-Fi APIs.

This document intentionally goes beyond
[`COMMERCIAL_GAP.md`](COMMERCIAL_GAP.md) and
[`NETUTILUS_PARITY.md`](NETUTILUS_PARITY.md): those tracks are shipped. The
remaining work is **trust, continuity, professional depth and engineering
speed**.

## Baseline

| Metric | Value |
| --- | ---: |
| Swift files (Models/Services/ViewModels/Views/Utils/CLI) | ~214 |
| Lines in those folders | ~42,000 |
| Test methods | 375 app + 6 core |
| Settings tabs | 11 |
| SwiftPM modules | 1 (`LanFiCore`, settings seed) |
| Distinct `LanFi.*` preference keys | 67 |
| `UserDefaults` call sites | 59 |
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
| P1.1 | Security Watch: rogue AP, evil twin, live deauth | New tool | High | M |
| P1.2 | Roaming and band-steering test | New tool | High | M |
| P1.3 | Client analytics from captures | New tool | Medium | M/L |
| P1.4 | Survey Planning 2.0 and active survey | Survey | High | L |
| P1.5 | Combined report / case file | Workflow | Medium | S/M |
| P1.6 | Shortcuts, App Intents, widgets, MCP actions | Integrations | Medium | M |
| P1.7 | Known networks inventory and Wi-Fi QR | Workflow | Low | S |
| P2.1 | Spectrum hub: Wi-Spy live, remote WLAN Pi, NetAlly | Hardware | High | L |
| P2.2 | BLE/Zigbee interference sources | Hardware | Low | M |
| P2.3 | Sandboxed MAS build split | Distribution | Medium | L |
| P2.4 | 802.11-2024/802.11bn decoder readiness | Future | Low | S |

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
- [ ] Add a launch-time self-check: if scan results have empty SSID/BSSID while
      Wi-Fi is on, show a diagnostic instead of an empty table.
- [ ] Document the permission reset risk after updates in `DISTRIBUTION.md`.

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

- [ ] Scan mode model (`active`, `passive`, `directed`) with a capability probe.
- [ ] Passive engine over the monitor interface, channel list and dwell time.
- [ ] 6 GHz PSC/RNR-aware channel list; SP/LPI labelling where available.
- [ ] UI: mode picker, unsupported-hardware explanation, progress.
- [ ] Tests for channel planning and merge behaviour; hardware smoke test.

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
- [ ] Deauth-burst (from captures) and roaming-failure events.
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
- [ ] Replace the text database with a binary trie if startup I/O becomes a
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
- [ ] Progressive heatmap tiles so a detail change paints before the whole grid
      is ready. NetSpot 6 advertises up to 18× faster generation.
- [x] Captures are memory-mapped (`mappedIfSafe`) instead of copied into
      resident memory before parsing.
- [ ] Stream packets and derive summary/clients/security from one parsed packet
      index instead of multiple passes.
- [ ] Exports and scheduled reports encode on the main actor; move to a
      background task.
- [x] Adaptive scan interval: 15 s in the background, 30 s in Low Power Mode,
      base interval when active, with a settings toggle and pure `ScanCadence`
      tests.

Acceptance: a 300-network scan applies filters and updates the table without a
visible hitch; the OUI warm path does no JSON decoding; a 500 MB–1 GB pcap
opens without a multi-gigabyte memory spike.

## P0.5 — Analyzer depth

- [x] Group by advertised AP name across 2.4/5/6 GHz; unnamed radios stay as
      separate BSSID groups.
- [ ] Infer co-located radios for APs that do not advertise a name.
- [x] History statistics (min/avg/max/p95) in the inspector.
- [ ] SSID overhead as a percentage of airtime (beacon airtime already exists).
- [ ] Decoder to 802.11-2024/WPA3 v3.5: RSN Override, Wi-Fi Alliance
      Capabilities, Extended BSS Load, MBSSID/non-transmitted BSSID, 320 MHz
      and MLO fields. WPA3 Transition is already decoded — do not redo it.
- [ ] 6 GHz PSC/RNR hints, SP/LPI labels and a “why is this AP not visible”
      explanation (macOS filters standard-power APs from active scans).
- [ ] Wi-Fi 8/802.11bn decoder versioning. Draft 2.0 entered working-group
      ballot in August 2026; certification is expected in 2028, so this is
      future-proofing, not a current blocker.

## P1 — New tools

- [ ] **Security Watch** — rogue AP/evil twin, security downgrade, live
      deauth/disassoc; build on the existing EAPOL/PMKID audit.
- [ ] **Roaming Test** — BSSID transitions, 802.11k/v/r, sticky client, band
      steering, reconnect time, packet loss.
- [ ] **Client Analytics** — per-client airtime, retries, association timeline,
      probes; correlate with Device Shelf.
- [ ] **Survey Planning 2.0** — antenna patterns/import, wall and floor
      materials, cutouts, floor alignment, real-time preview, calibration
      against measured samples. `SurveyPredictor` currently uses free-space
      path loss plus a fixed 12 dB per-floor loss; replace it with a
      material-aware model.
- [ ] **Active Survey** — throughput and latency per sample point, auto-walk
      sampling every N seconds/metres, before/after comparison and a
      multi-floor diff report.
- [ ] **Combined report** — one PDF/HTML with scan, survey, security,
      diagnostics and speed test; branding and redaction.
- [ ] **Shortcuts/App Intents/widgets** — scan, export, capture, speed test.
- [ ] **MCP 2.0** — live actions (`scan now`, `start capture`, `survey sample`),
      not only the read-only snapshot.
- [ ] **Known Networks / Wi-Fi QR** — inventory of saved networks, security and
      last-joined metadata, plus a guest-network QR. Read-only first; editing
      known networks is a separate, riskier step.

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
- [ ] Speed test: keep `networkQuality` as the transport but add a bufferbloat
      grade and history per network over time.

---

## Engineering work

### Modularity

- [x] Seed `LanFiCore` as a SwiftPM library with typed settings and its own
      `swift test` target. Models, parsers, analyzers and stores still live in
      the app target.
- [ ] Extract the rest of `LanFiCore` (models, parsers, analyzers, stores) and
      `LanFiProbes` (ICMP/TCP/DNS/TLS); this needs a public-API pass.
- [ ] Stop listing sources three times in `project.yml`; app, tests and CLI
      depend on packages instead.
- [x] Split `ToolkitViewModel` (1311 → 44 lines + 15 focused files).
- [x] Split `MainTableView` (1314 → 252 lines + 6 focused files).
- [ ] Split `AnalyzerViewModel` (1490) and `MCPToolkit` (1280).
- [x] Centralize `ToolboxTool` metadata in one `ToolRegistry` table, with a
      test that every tool has exactly one descriptor.
- [ ] Move view routing and the MCP tool spec into the registry so a new tool
      is one descriptor plus one view.
- [x] Introduce typed `AppSettings` with defaults, legacy migration and
      export/import; General Settings already uses it.
- [ ] Migrate the remaining 60-ish string keys (monitor, capture, survey,
      diagnostics, MCP) into `AppSettings`.
- [ ] Add dependency seams (clock, scanner, notifications, file store) and
      enable Swift 6 strict concurrency for the core module.
- [x] Make `swift-format` blocking in CI and run `swift test` for the core
      package.
- [ ] Add a macOS 13/14/15/26 matrix, UI smoke tests and performance budgets.

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
   history stats; P0.3 MVP.
2. **Next (3–6 weeks):** P0.2 passive scan; P1 Security Watch and Roaming Test;
   combined report; Shortcuts/App Intents; MCP actions.
3. **Later (quarter):** Survey Planning 2.0, spectrum hub, client analytics,
   sandbox/MAS split, BLE/Zigbee, 802.11bn readiness.

If the product stays a free home analyzer, stop after step 1 plus Security
Watch/Roaming. If it targets WiFi Explorer Pro, passive scan, history and
spectrum are required.

## Non-goals

- Ekahau-class predictive enterprise design and cloud planning. NetSpot 6
  multi-floor planning with antennas and floor materials is the prosumer bar,
  not a reason to build an enterprise RF planner.
- Cloud accounts, mandatory telemetry or a hosted dashboard.
- Windows/Linux ports before macOS signing and distribution are trustworthy.

## Sources

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
