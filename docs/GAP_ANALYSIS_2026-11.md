# Gap analysis — November 2026

Status: **active plan**. Baseline: LanFi 5.3.0 (build 69).
Scope: post-Netutilus parity, compared with WiFi Explorer Pro 3.10, NetSpot 6,
Airtool 2, the public macOS Wi-Fi APIs, and the menu-bar/utility segment covered
in [`REFERENCE_APPS_REVIEW_2026-11.md`](REFERENCE_APPS_REVIEW_2026-11.md)
(NetWorker Pro, AirRadar 8, PeakHour 6 and an Unstore buyer's guide).

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
- [ ] Decoder to 802.11-2024/WPA3 v3.5: RSN Override, Wi-Fi Alliance
      Capabilities, Extended BSS Load, MBSSID/non-transmitted BSSID, 320 MHz
      and MLO fields. WPA3 Transition is already decoded — do not redo it.
- [x] 6 GHz PSC hints and a “why is this AP not visible” explanation
      (`VisibilityAdvisor`): PSC vs non-PSC channels, DFS sharing and hidden
      SSIDs, plus the same hint in the empty workspace.
- [ ] SP/LPI power-mode labels: CoreWLAN does not expose the 6 GHz power mode,
      so this needs a capture-based source rather than a beacon guess.
- [ ] RNR (Reduced Neighbor Report) decoding into neighbouring-channel hints;
      a decoder change in `InformationElementParser`, not a UI change.
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
- [ ] **Connections** — open TCP/UDP sockets with process name, PID, local and
      remote endpoint, state and bytes; grouped by process. Data source is
      `nettop -P -x -l 1` (parsed, no private APIs) with `lsof`-style fallback.
      Read-only: LanFi never kills a connection. Redact remote hosts in exports.
- [ ] **Per-process traffic** — the NetWorker "Processes" screen: per-PID
      received/sent deltas over a rolling window, sorted, with the app's own
      traffic excluded. Ship it behind an explicit toggle because parsing
      process tables is the most privacy-sensitive surface in the app; document
      that nothing leaves the machine.
- [ ] **Traffic accounting** — day / week / month / total volumes per interface
      from the same sampler, stored locally next to `speed-tests.json`, with a
      reset control and CSV export.
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
- [ ] Speed test: keep `networkQuality` as the transport but add a bufferbloat
      grade and history per network over time.
- [ ] Connected-link telemetry: poll `CWWiFiClient().interface()` for
      `transmitRate()`, `noise()`, `ssid()`, `bssid()` and the negotiated PHY on
      a slow timer (5 s) and keep it in the Monitor store next to RSSI, so the
      Link inspector can show rate, PHY, width, streams and MCS/NSS over time.
      CoreWLAN does not expose MCS or NSS for the live link; derive NSS from the
      HT/VHT/HE capability IEs of the connected BSSID and label the value as
      capability, not measurement.
- [ ] Noise in the history chart: `SignalHistoryView` plots RSSI only. Add the
      AirRadar-style mode switch (signal / noise / both) using the noise value
      already carried by `NetworkModel`.
- [ ] Wi-Fi card selection: `WiFiScanner` accepts a preferred interface name but
      nothing in the UI sets it. Add an interface picker for multi-radio Macs and
      a "scanning with" label next to the scan control.
- [ ] SNMP/UPnP polling for router/NAS targets (PeakHour pattern): read-only
      v2c GET of standard interface counters plus SSDP discovery, with a strict
      timeout and no credential storage. Later bucket; only if the menu-bar
      meter proves useful.

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
      - [ ] Promote the toolkit components into shared ones (`AppCard`,
            `SectionLabel`, `StatusPill`, `StatTile`, `MetricRow`, `PillButton`,
            `EmptyState`, `Banner`) and migrate every screen to them; delete the
            per-view copies. `AppCard`, `SectionLabel`, `StatusPill`, `StatTile`
            and `BandChip` exist and the RF overview uses them; every other
            screen still hand-rolls its cards.
      - [ ] Tests: a snapshot-free unit test that every registered tool renders a
            `SectionLabel`+`AppCard` root (pure view-model assertions), and a
            lint rule of thumb in `CONTRIBUTING.md`: no new literal `cornerRadius`
            or `opacity(0.0x)` in `Views/` without a token. The RF overview has
            its own geometry tests; this component-level check is still open.
- [ ] **D2 — Hero RF overview, first run and empty states.** The overview,
      first run and empty states shipped 2026-11-16; the menu-bar open target is
      still open.
      - [x] All-band overview (P1.10): 2.4/5/6 GHz columns, AP spans with overlap
            shading, connected AP highlighted, recommended channel as a marker,
            legend in plain words ("channels other networks also use are
            shaded").
      - [ ] Make it the `MenuBarExtra` "Open" target; fresh installs already
            default to it and Insights stays one click away.
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
      - [ ] One chart style (axes, grid, tooltip, selection band, empty state) used
            by `SignalHistoryView`, `SpectrumView`, `HardwareSpectrumView`,
            occupancy and toolkit latency graphs. `ChartStyle` now defines the
            axis, grid, cursor and tooltip tokens and the history and occupancy
            charts use it; the Canvas spectrum and toolkit latency graphs still
            hand-roll their styling.
      - [x] History chart mode switch: signal / noise / both (P2.6). Noise is
            dBm-only, so percent mode stays signal-only.
      - [ ] Inspector restructure: a fixed "Link" block (rate, MCS/NSS, width,
            streams, cipher, band) above the existing six sections, sticky while
            scrolling, with the same block reusable as a printable per-network
            page for reports.
- [ ] **D5 — Menu-bar and window chrome.**
      - [ ] Menu-bar sparkline (P0.6) drawn with the tokens, legible as a template
            image in light and dark menu bars.
      - [ ] One toolbar treatment across the Wi-Fi workspace and toolkit: same
            control heights, same pill spacing, same separators, same
            icon+label rule.
      - [ ] Icon audit: every icon-only control gets an accessibility label, a
            tooltip and a consistent SF Symbol family; the `Planned` badge stays
            but adopts the token palette.
- [ ] **D6 — Settings, Help and onboarding.**
      - [x] Settings is no longer 11 tabs: a grouped sidebar (Application /
            Analysis / Integrations) with the last section remembered in
            `LanFi.settings.section`, over the unchanged screens. Deep links use
            the same settings window.
      - [x] Appearance, density and the menu-bar meter live in General, next to
            the display and toolbar options.
      - [ ] Help window: task-oriented sections with one screenshot each, plus an
            in-app "what is this?" popover on the main chart.
- [ ] **D7 — Accessibility visual pass.**
      - [ ] Colour-blind-safe palette option (semantic shapes/labels alongside
            colour), contrast check on every token pair at 4.5:1, reduce-motion
            respect for heatmap streaming and scan animation.
      - [ ] Dynamic Type on macOS via `dynamicTypeSize` where layouts allow, and a
            fixed-size table path that degrades gracefully.
      - [ ] Hands-on VoiceOver pass with the remaining screens (already an open
            item in the README).
- [ ] **D8 — Release visual assets.**
      - [ ] A repeatable screenshot script (seeded data, fixed window size, light
            and dark) so README, site and release notes never go stale.
      - [ ] Refresh `docs/images/` and `site/` gallery from that script; keep the
            icon generator (`scripts/make_icon.swift`) as the only icon source.

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
- [ ] Extract the rest of `LanFiCore` (models, parsers, analyzers, stores) and
      `LanFiProbes` (ICMP/TCP/DNS/TLS); this needs a public-API pass.
- [ ] Stop listing sources three times in `project.yml`; app, tests and CLI
      depend on packages instead.
- [x] Split `ToolkitViewModel` (1311 → 44 lines + 15 focused files).
- [x] Split `MainTableView` (1314 → 252 lines + 6 focused files).
- [ ] Split `AnalyzerViewModel` (1490) and `MCPToolkit` (1280); export
      responsibilities are now extracted, but the view model is still large.
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
   combined report; Shortcuts/App Intents; MCP actions; D4–D6.
3. **Later (quarter):** P1.8 connections and per-process traffic; P1.9 GPS map;
   P2.6 link telemetry; Survey Planning 2.0; spectrum hub; client analytics;
   sandbox/MAS split; BLE/Zigbee; 802.11bn readiness; D7–D8.

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

- [Reference apps review, November 2026](REFERENCE_APPS_REVIEW_2026-11.md)
  (Unstore buyer's guide, NetWorker Pro, AirRadar 8, PeakHour 6)
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
