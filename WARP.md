# WARP.md — working on LanFi

This file orients coding agents and contributors. See also `CONTRIBUTING.md`.

## Project overview

LanFi is a native macOS 13+ Wi‑Fi analyzer: SwiftUI shell, an AppKit
`NSTableView` bridge for the network list, Swift Charts for history, and a
Canvas-based spectrum view. Scanning uses only public CoreWLAN APIs. No
analytics, networking, accounts or third-party SDKs.

## Essential commands

```bash
xcodegen generate                 # project.yml is the source of truth
open LanFi.xcodeproj               # develop/run
./build.sh                        # universal Release app + ad-hoc signature

xcodebuild test \
  -project LanFi.xcodeproj \
  -scheme LanFi \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

./scripts/lint.sh
./scripts/format.sh
```

Outputs:
- Debug: `build/DerivedData/Build/Products/Debug/LanFi.app`
- Release: `build/LanFi-Universal/LanFi.app`

If you add/move/delete files, run `xcodegen generate` and commit the regenerated
`LanFi.xcodeproj/project.pbxproj` and `Info.plist`.

## Architecture

- `LanFiApp.swift` — `@main`, single `AnalyzerViewModel` and
  `AppUIState`, main `WindowGroup(id: "main")`, `MenuBarExtra`, app commands.
- `Models/NetworkModel.swift` — immutable `NetworkModel` and `InformationElement`
  value types plus `WiFiBand`/`WiFiStandard` enums and display helpers.
- `Services/WiFiScanner.swift` — `actor WiFiScanner`; performs CoreWLAN scans
  off the main thread and builds `NetworkModel` values (security, band, width,
  rates, channel utilization, parsed IE fields).
- `Services/InformationElementParser.swift` — pure 802.11 IE decoder. Must not
  import CoreWLAN/SwiftUI so tests can compile it directly.
- `Models/ColumnCatalog.swift` — column ids, default titles/widths/order and
  visibility. `Models/SignalDisplayMode.swift` — dBm/percent setting.
- `Models/ProtocolProfile.swift` / `Services/ProtocolAnalyzer.swift` — six block
  profiles (radio, security, roaming, spectrum, format, vendor) and coverage.
- `Models/DiagnosticsModel.swift` / `Services/DiagnosticsEngine.swift` — link,
  IPv4, gateway, DNS, captive-portal and latency checks with injectable transport.
- `Models/NetworkGrouping.swift` — SSID/band/vendor/security grouping.
- `Models/NetworkAnnotation.swift` — local alias/tags/notes and store.
- `Models/ScanSession.swift` — saved sessions (Codable network snapshots).
- `Services/PcapExporter.swift` — synthetic beacon pcap export.
- `Models/Survey.swift` / `ViewModels/SurveyViewModel.swift` — floor-plan survey
  and heatmap samples.
- `Services/UpdaterController.swift` — Sparkle 2 update controller.
- `Services/NetworkColumnFormatter.swift` — pure cell text and sort comparison
  for every column, so the whole catalog can be tested without a UI.
- `Services/NetworkAnalyzer.swift` — pure scoring/analysis:
  - 0–100 quality score from signal, SNR, congestion, utilization, security;
  - spectral-overlap fractions from primary channel + width;
  - ranked channel recommendations for 2.4/5/6 GHz (20/80 MHz candidates, DFS);
  - security findings (open/WEP/legacy WPA/WPS/PMF) and performance issues.
- `ViewModels/AnalyzerViewModel.swift` — `@MainActor` state: scan timer, merge
  and expiry, filtering/sorting, preferences, CSV/JSON export. Column metadata
  lives in `Models/ColumnCatalog.swift`; formatting is delegated to
  `NetworkColumnFormatter`.
- `ViewModels/AppUIState.swift` — sidebar/inspector/bottom-tab state.
- `Views/WiFiTableView.swift` — `NSViewRepresentable` around `NSTableView`,
  column diff/reorder/resize persistence, context menus, selection sync.
- `Views/MainTableView.swift` — toolbar, split panes, inspector, permission
  onboarding, status bar, bottom-panel tabs.
- `Views/InsightsView.swift` — summary cards, channel recommendations, grouped
  security findings, occupancy chart.
- `Views/ProtocolsView.swift` — block cards and all-network protocol coverage.
- `Views/DiagnosticsView.swift` — diagnostics status, check grid and history.
- `Views/SurveyView.swift` — floor-plan import, sample placement and heatmap.
- `ViewModels/DiagnosticsViewModel.swift` — diagnostics run/monitor state.
- `ViewModels/SurveyViewModel.swift` — survey project and floor-plan state.
- `Views/SpectrumView.swift` — per-band Canvas spectrum with hit testing.
- `Views/SignalHistoryView.swift` — Swift Charts signal history with cursor.
- `Views/RawDataView.swift` — expandable IE table.
- `Models/ToolboxTool.swift` — toolkit catalogue and sidebar sections.
- `Models/ToolkitModels.swift` — probe value types, DNS records, verdicts.
- `Models/MTRModels.swift`, `SpeedTestHistory.swift`, `UptimeModels.swift`,
  `LANModels.swift`, `Iperf3Models.swift` — monitoring and toolkit data.
- `Services/Toolkit/` — native probe layer: `DNSMessage`, `DNSClient`,
  `PingService`, `PortScanner`, `TLSCertificateInspector`, `TracerouteRunner`,
  `TracerouteParser`, `MTRService`, `LANScannerService`, `BonjourDiscovery`.
  Pure codecs/parsers must stay testable headless.
- `Services/UptimeMonitor.swift`, `UptimeStore.swift` — scheduled HTTP/TCP
  checks, transitions, UserNotifications and seven-day history.
- `Views/Toolkit/` — the Network Toolkit window, grouped custom sidebar and
  per-tool screens.
- `ViewModels/ToolkitViewModel.swift` — per-tool state and cancellation.
- `Utils/LocationManager.swift` — CLLocation authorization wrapper.
- `Utils/OUIParser.swift` — bundled IEEE OUI lookup (randomized MAC detection).

## Data flow

1. `AnalyzerViewModel.init` loads preferences, starts a `Timer` (default 3 s)
   and requests Location authorization.
2. Each tick calls `WiFiScanner.scan()` (actor, off main thread).
3. Results are merged into `persistentNetworks`, `firstSeen`/`lastSeen`/`count`
   updated, stale entries dropped, signal history appended.
4. `NetworkAnalyzer.analyze` recomputes metrics and recommendations over **all**
   persistent networks (not just filtered rows).
5. `applyFilters` produces the visible/sorted `networks` array.
6. SwiftUI updates the AppKit table; columns are diffed from
   `columnDefinitions`.

## Persistence keys

- `WifiColumns_v4` — JSON `[ColumnDefinition]` (order/width/visibility/title).
- `LanFi.tabLayoutVersion` — one-time migration to the Insights-first tab layout.
- `RefreshIntervalSeconds` — scan interval.
- `LanFi.filterBand24|filterBand5|filterBand6` — band filters.
- `LanFi.minSignal`, `LanFi.removeAfter` — signal threshold and expiry.
- `LanFi.signalUnit`, `LanFi.highlightConnected` — display options.
- `LanFi.sortKey`, `LanFi.sortAscending` — table sort.
- `LanFi.showSidebar`, `LanFi.showInspector`, `LanFi.bottomTab` — layout
  (`0` Insights, `1` Spectrum, `2` History, `3` Protocols, `4` Interfaces,
  `5` Raw Data, `6` Diagnostics).
- `LanFi.groupMode` — none/SSID/band/vendor/security grouping.
- `LanFi.speedTestSchedule`, `LanFi.lanGuardEnabled` — toolkit schedules/guard.
- `speed-tests.json`, `uptime.json`, `lan-guard.json` live under
  `~/Library/Application Support/LanFi/` (50 speed runs, seven days of uptime
  checks, known LAN device keys).
- Session, annotation and survey files live under
  `~/Library/Application Support/LanFi/{Sessions,annotations.json,Surveys}`.
- Window frame is managed by SwiftUI/AppKit.

## Adding a column

1. Add a property to `NetworkModel` and populate it in `WiFiScanner` (or extend
   `InformationElementParser` for IE-derived values).
2. Add a case to `ColumnId` and handle it in:
   - `defaultTitle`, `defaultWidth`, `defaultAlignment`, `defaultVisibility`;
   - `ColumnId.displayOrder`;
   - `AnalyzerViewModel.textForColumn` and `compare(_:_:by:)`.
3. No change is needed in `WiFiTableView`; it renders via `textForColumn`.
4. Add the field to JSON export (`networkJSON`) if it is user-relevant.
5. Bump the `WifiColumns_*` key only for breaking column migrations.

## Diagnostics, sessions and survey

- Diagnostics run on demand and optionally every 60 seconds. The engine accepts
  an injected `DiagnosticsTransport`, so tests never touch the network.
- Sessions pause live scanning; `Resume Live Scan` clears the session and
  restarts the timer.
- Annotations are stored per network id (BSSID when available) and saved with a
  0.5 s debounce.
- Surveys copy the floor plan into a per-project directory and store normalized
  sample coordinates, so window resizing does not move points.

## Vendor database

`Resources/oui` is generated from the IEEE MA-L/MA-M/MA-S registries and the
Wireshark `manuf` file. Prefixes are 6, 7 or 9 hex characters and the lookup
uses the longest match. Refresh it with:

```bash
python3 scripts/update_oui.py
```

## Network Toolkit

`Tools → Network Toolkit…` (⇧⌘T) opens `NetworkToolkitView`, a separate window
with a custom grouped sidebar. It shares `DiagnosticsViewModel` and
`InterfacesViewModel` with the main window. `ToolboxTool` owns the catalogue,
`isAvailable` marks screens that are wired, and planned rows stay visible with a
"Planned" badge.

The probe layer is transport-injected: ping, port probing and TLS take protocols
so tests never touch the network. ICMP uses the unprivileged `SOCK_DGRAM` socket
(`IP_TTL` is ignored there, so traceroute uses `/usr/sbin/traceroute`, which is
setuid root on macOS). Deep link: `lanfi://toolkit/<tool>`.

Uptime Monitor reuses the existing `MenuBarExtra` and `UserNotifications`;
there is no second menu-bar item. LAN Scanner prefers `/usr/sbin/arp`, but macOS
can hide the ARP table from a non-privileged child process until Local Network
access is granted. It then falls back to an ICMP/TCP sweep, so IP/port results
still work; MAC, vendor and TCP probes need that permission. Bonjour browsing
requires the `NSBonjourServices` entries in `Info.plist`.

## Testing

`LanFiTests` compiles `NetworkModel`, `NetworkAnalyzer`,
`InformationElementParser` and `OUIParser` directly (no app host, no
CoreWLAN), so tests run headless. Add pure-logic tests for scoring, overlap,
recommendations, parsing and export DTOs. Avoid UI tests that require Location
permission. Toolkit tests cover DNS wire parsing, MTR aggregation, uptime
transitions/stores, LAN ARP/subnet/guard logic, speed history and iperf3 JSON.

## Automation and release

- `scripts/autopush.sh` commits/pushes meaningful changes; `--install-hook`
  installs a `post-commit` hook. It refuses credentials/oversized files and
  rebases on non-fast-forward pushes.
- Sparkle 2 update checks use `SUFeedURL` →
  `https://github.com/zheltukheen/lanfi/releases/latest/download/appcast.xml`.
  The release workflow signs the ZIP with the `SPARKLE_PRIVATE_KEY` secret and
  attaches `appcast.xml`.
- `Casks/lanfi.rb` is updated automatically on release.
- CI (`.github/workflows/ci.yml`) runs swift-format lint, XCTest and a universal
  Release build on macOS 15.
- Release (`.github/workflows/release.yml`) is triggered by `v*` tags: verifies
  the tag against `project.yml`, tests, builds, packages ZIP + DMG + SHA-256,
  and publishes notes from `CHANGELOG.md`.
- Stable download links: every release also uploads `LanFi.dmg`, `LanFi.zip`,
  `LanFi-CLI.zip`, `LanFi.sha256` and `LanFi.version` under constant names, so
  `https://github.com/zheltukheen/lanfi/releases/latest/download/LanFi.dmg`
  always resolves to the newest build. The versioned files
  (`LanFi-<version>.dmg` in `releases/download/v<version>/`) stay immutable and
  are what Sparkle, the Homebrew cask and pinned downloads use.
- `https://zheltukheen.github.io/lanfi/download` (`site/download/index.html`) is
  the short, version-free landing link; it forwards to the always-latest DMG.
- `./release.sh X.Y.Z` runs lint + XCTest (skip with `--skip-tests`), updates
  `project.yml`, regenerates the project, commits, pushes and tags.
- `scripts/make_icon.swift` redraws the icon master (1024², CoreGraphics) and
  rewrites the full `AppIcon.appiconset` plus `docs/images/lanfi-icon.png` and
  `site/assets/lanfi-icon.png`; `--preview` writes `build/icon-preview.png`.

## Constraints

- Public CoreWLAN only; no private APIs, no `airport` CLI parsing.
- Keep scanning/parsing off the main thread; UI state stays `@MainActor`.
- Pure analysis belongs in `NetworkAnalyzer`/`InformationElementParser` with
  tests.
- No telemetry or network calls. Location is only for SSID/BSSID visibility.
- Prefer semantic colors; charts must remain legible in dark and light mode.
