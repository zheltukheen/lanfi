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
./scripts/visual-check.sh      # seeded snapshots: screenshots/, docs/images/, site/assets/
```

Outputs:
- Debug: `build/DerivedData/Build/Products/Debug/LanFi.app`
- Release: `build/LanFi-Universal/LanFi.app`

If you add/move/delete files, run `xcodegen generate` and commit the regenerated
`LanFi.xcodeproj/project.pbxproj` and `Info.plist`.

Sources are declared once, as folders: `LanFi`, `LanFiTests` and `lanfi-cli`
all take `Models`, `Services`, `Utils` (and `CLI`) rather than per-file lists.
A new shared file therefore reaches the app, the CLI and the tests without any
`project.yml` edit; do not reintroduce a template or a hand-written source
list, which is what used to drift (`SharedToolchainSources` was removed for
that reason). The test bundle declares the Sparkle package because
`Services/UpdaterController.swift` lives in the shared folder; the CLI excludes
that one file and does not link Sparkle, so the standalone binary runs without
an app bundle.

## Architecture

- `LanFiApp.swift` — `@main`, single `AnalyzerViewModel` and
  `AppUIState`, main `WindowGroup(id: "main")`, `MenuBarExtra`, app commands.
- `Models/NetworkModel.swift` — immutable `NetworkModel` and `InformationElement`
  value types plus `WiFiBand`/`WiFiStandard` enums and display helpers.
- `Models/ScanModePlan.swift` — P0.2 scan modes (`active`, `passive`,
  `directed`), the hardware capability rules (including the Apple N1 channel-
  hopping limit), the PSC/RNR-aware 6 GHz channel planner and progress values.
  `Services/ScanHardwareProbe.swift` fills the profile from `sysctl` and
  CoreWLAN; `Services/PassiveScanEngine.swift` runs the monitor capture, hops
  channels and maps beacons; `Views/WiFiWorkspace/PassiveScanSheet.swift` is the
  mode picker and plan/progress sheet.
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
- `Models/ThroughputSample.swift` / `Services/ThroughputSampler.swift` /
  `ViewModels/MenuBarMeterModel.swift` / `Views/MenuBarSparkline.swift` — the
  menu-bar live meter: pure rate/smoothing/formatting values, the `getifaddrs`
  counter reader, the 60-sample rolling model (2 s active, 30 s background) and
  the `Canvas` sparkline used by the `MenuBarExtra` label.
- `Views/Toolkit/WhoisGeoIPToolView.swift` and
  `Views/Toolkit/TracerouteTabsView.swift` — the two merged screens. Tools
  that answer the same question share a `ToolScreen` and a tab strip; their
  `ToolDescriptor.showsInSidebar` is false so the sidebar lists the host once,
  while the deep link still selects the tab.
- `Views/Toolkit/OverviewDashboardView.swift` — the default screen
  (`ToolboxTool.overview`). It composes the shared services
  (`ConnectivityWatchdog`, `GatewayGuard`, `VPNGuard`, `TrafficAccounting`,
  `MenuBarMeterModel`, `UptimeMonitor`, `LinkAutomation`) into one summary; the
  Wi-Fi analyzer is one tool in the sidebar, not the root screen. Nothing here
  starts its own timer: a new card must read an existing service.
  `NetworkToolkitView` and the dashboard take `meter` as an explicit
  `@ObservedObject` with `MenuBarMeterModel.shared` as the default, so previews,
  the snapshot harness and the smoke test build the screen without the app's
  environment and without a second sampler. The layout is a fixed set of rows
  (link + internet, four metric tiles, live throughput + uptime, bands +
  channels, uniform quick-action grid), and every button in a row fills its
  cell, so control sizes no longer shift with the text.
- `Views/AppTable.swift` — the shared SwiftUI table builder; its column
  headers sort on click, and rows can carry a selection binding and a context
  menu (`init(columns:rows:initialKey:selection:rowMenu:)`) so a screen does not
  need a native `Table` for interactivity. Whois events, Path Check, the TLS
  chain, DNS answers, Ping, MTR, Port Scan (TCP and UDP), HTTP Traffic, iperf3
  history, Uptime checks, Network Monitor routes and the comparison panels use
  it. The Device Shelf, LAN Scanner and Client Analytics derive their
  `AppTable` columns from an existing sort list where one exists, so the header
  and the sort values cannot drift.
  Offline Capture uses it as well (beacons plus the Clients and Security sheet
  tables), and so do Connections and Process Traffic. Hierarchical screens pass
  an `AppTableGrouping`, whose `isSectionStart` marks a group row: the sorter
  orders sections by their header value and sorts each section's children among
  themselves, so a group always stays above its own rows. A column can opt out
  of sorting (`isSortable: false`) for action columns, and `onActivate` runs on
  a whole-row click, which is how a group expands. The Wi-Fi analyzer keeps its
  own sort/filter UI by design. Columns are
  declared with the `@ViewBuilder` initializer, so a cell is written as a
  normal view instead of a hand-wrapped `AnyView`.
- `Models/CommandIndex.swift` + `Views/CommandPaletteView.swift` — the ⌘K
  palette. `CommandIndex.all` is built from the sidebar's `ToolboxTool` list,
  `SettingsSection.allCases` and the Wi-Fi workspace panels, so a new screen is
  searchable as soon as it registers; ranking is exact title, prefix,
  substring, keyword, subtitle, category, and `Tests/CommandIndexTests` pins it.
  `perform(_:)` in `NetworkToolkitView` routes a hit to a tool, a bottom tab or
  the Settings window.
- `Views/AppControls.swift` — the single control kit (`AppButton`,
  `AppIconButton`, `AppListRow`, `AppSearchField`, `ToolkitHeaderBar`); route
  new buttons, lists and tool headers through it. `AppButton(localized:)`
  takes a title that is already localized at runtime (a computed `String`).
  Menus, context menus and confirmation dialogs keep plain `Button`s on
  purpose — a custom button style does not render inside them.
- `Models/SignalBarMetrics.swift` — the pure arithmetic behind the signal and
  quality bars; the cell measures the text with
  `NSAttributedString.size(withAttributes:)` (never `intrinsicContentSize`,
  which is -1 before layout) and `SignalBarMetricsTests` covers a narrow and a
  wide column.
- `Models/AppTrafficHistory.swift` / `Services/AppTrafficHistoryService.swift` —
  P3.6: hourly per-app byte buckets (`app-traffic-history.json`), seven-day
  retention, CSV export, LanFi's own traffic excluded.
- `Models/TrafficAccounting.swift` / `Services/TrafficAccountingService.swift` —
  P2: `TrafficLedger` (per-day, per-interface volume, day keys in the user's
  calendar) and the minute poll that writes `traffic-accounting.json`.
- `Models/LinkAutomation.swift` / `Services/LinkAutomationService.swift` —
  P3.8: the edge-triggered Wi-Fi/Ethernet policy, hardware-port parsing and the
  poller that writes `networksetup -setairportpower` (off by default).
- `Services/SecurityGuardSupport.swift` — `PollingGuard` (timer, tolerance,
  overlap guard and the published `isSampling` / `lastCheckedAt`), the
  `SecurityEvent.post` channel both guards share, and `ShellOutput.run`. Add a
  new guard by subclassing `PollingGuard` and overriding `performSample()`;
  do not add another timer or another `Notification.Name`.
- `Models/VPNGuard.swift` / `Services/VPNGuardService.swift` — P3.4: VPN
  detection, the `scutil --dns` / `netstat` parsers, the DNS and IPv6 leak
  verdicts, and the poller that posts `vpnDropped` / `vpnLeak` events.
- `Models/GatewayIntegrity.swift` / `Services/GatewayGuardService.swift` — P3.7:
  the gateway ARP watch, the DNS-answer comparison, and the guard that posts
  `gatewayChanged` / `dnsMismatch` Monitor events through `.lanFiSecurityEvent`.
- `Models/ServiceDescription.swift` / `Services/ServiceDescriptionResolver.swift`
  — P3.10: the bundled offline domain/process description catalogue and the
  opt-in on-device model (`FoundationModels`, macOS 26+) used for unknown names
  in Connections and the HTTP traffic inspector.
- `Models/SSHLaunch.swift` / `Services/TerminalLauncher.swift` — P3.9: the
  fully quoted `ssh` command for a saved sensor or an SSH-capable LAN device and
  the `osascript` hand-off to Terminal. No Keychain access, no passwords.
  `open(command:)` is `async` and runs the AppleScript in a detached task: the
  first call can wait on the Automation permission sheet, and blocking the
  button handler there would freeze the window. Both call sites (Remote Sensors
  and the LAN Scanner context menu) await the result and show `message` when
  the request is refused.
- `Models/ListenerWatch.swift` / `Services/ListenerWatchService.swift` — P3.1:
  the listener summary, the endpoint exposure classifier (`SocketExposure` in
  `Models/OpenConnections.swift`), the sample diff and the `ListenerWatcher`
  that samples `lsof` every 30 s behind the persisted "Watch listeners" toggle.
- `Models/ConnectivityWatchdog.swift` / `Services/ConnectivityWatchdogService.swift` —
  P3.3: the online / captive-portal / offline verdict, its two-strike
  hysteresis, the probe classifier and the notification policy, plus the timed
  `NWPathMonitor` service behind the menu-bar state, the latency metric and the
  Shortcut intent.
- `Models/TablePresentation.swift` — table density presets, the signal/quality
  bar values and header decoration, all pure and tested. In-cell visuals are
  allowed in the Signal and Quality columns only, beside the number; every other
  column stays text-only (see the presentation rules in the gap analysis).
- `Services/NetworkColumnFormatter.swift` — pure cell text and sort comparison
  for every column, so the whole catalog can be tested without a UI.
- `Models/RoamingTest.swift` — 802.11k/v/r capability detection from IEs and
  `fastTransition`, BSSID transitions from monitor samples, and sticky-client /
  band-steering verdicts. See `Views/Toolkit/RoamingTestToolView.swift`.
- `Models/KnownNetwork.swift` — `networksetup` output parser and the `WIFI:`
  QR payload with spec escaping. `Services/KnownNetworksService.swift` shells
  out read-only; LanFi never reads saved Wi-Fi passwords.
- `Models/LinkTelemetry.swift` / `ViewModels/ConnectedLinkMonitor.swift` /
  `Views/WiFiWorkspace/LinkInspectorSection.swift` — 5 s link sampling and the
  inspector's Link block. NSS is a beacon capability, not a live measurement.
- `Models/CombinedReport.swift` / `Services/CombinedReportExporter.swift` — the
  pure combined-report value and its self-contained HTML renderer; exported
  from the Data menu.
- `Models/SixGHzOperationInfo.swift` — decodes the HE Operation element's 6 GHz
  Operation Information (primary channel, width, duplicate beacon, regulatory
  info → LPI/SP/VLP, CCFS0/1, minimum rate). CoreWLAN does not expose the power
  mode, so this is the beacon source used by the inspector.
- `Models/ReducedNeighborReport.swift` — decoder for element 201 (TBTT header,
  operating class, channel, offset, BSSID, short SSID, BSS parameters, 20 MHz
  PSD, MLD parameters).
- `Models/SecurityWatch.swift` — read-only Security Watch heuristics: evil twin
  and downgrade checks inside one SSID, randomized-BSSID detection and recent
  captured deauth bursts. Pure `SecurityWatchEvaluator`; the screen is
  `Views/Toolkit/SecurityWatchToolView.swift`. It never frames or injects.
- `Services/LanFiIntents.swift` — App Intents (scan, connected network, speed
  test) and Shortcut phrases.
- `Services/NetworkAnalyzer.swift` — pure scoring/analysis:
  - 0–100 quality score from signal, SNR, congestion, utilization, security;
  - spectral-overlap fractions from primary channel + width;
  - ranked channel recommendations for 2.4/5/6 GHz (20/80 MHz candidates, DFS);
  - security findings (open/WEP/legacy WPA/WPS/PMF) and performance issues.
- `ViewModels/AnalyzerViewModel.swift` — `@MainActor` dependencies, published
  state, initialisation and small helpers; behaviour lives in the
  `ViewModels/Analyzer/AnalyzerViewModel+*.swift` extensions (scanning,
  filtering, workspace queries, sessions, export, persistence). Scan timer,
  merge/expiry, preferences and CSV/JSON export stay inside those extensions.
  Column metadata lives in `Models/ColumnCatalog.swift`; formatting is
  delegated to `NetworkColumnFormatter`.
- `ViewModels/AppUIState.swift` — sidebar/inspector/bottom-tab state.
- `Views/WiFiTableView.swift` — `NSViewRepresentable` around `NSTableView`,
  column diff/reorder/resize persistence, context menus, selection sync.
- `Views/MainTableView.swift` — the Wi-Fi workspace: toolbar, top-row
  filter bar, split panes, inspector, permission onboarding, status bar,
  bottom-panel tabs. It is embedded in the toolkit (`embedded: true`).
  `Models/WorkspacePlaceholder.swift` decides what an empty workspace says;
  `Views/WiFiWorkspace/FirstRunView.swift` is the one-time onboarding sheet.
- `Models/VisibilityAdvice.swift` — plain-language PSC/DFS/hidden-SSID hints used
  by the inspector and the empty workspace.
- `Views/FilterBarView.swift` — band chips, signal threshold, sort, grouping,
  saved rules and quick filters in the window's top row.
- `Views/InsightsView.swift` — summary cards, channel recommendations, grouped
  security findings, occupancy chart.
- `Views/ProtocolsView.swift` — block cards and all-network protocol coverage.
- `Views/DiagnosticsView.swift` — diagnostics status, check grid and history.
- `Views/SurveyView.swift` — floor-plan import, sample placement and heatmap.
- `ViewModels/DiagnosticsViewModel.swift` — diagnostics run/monitor state.
- `ViewModels/SurveyViewModel.swift` — survey project and floor-plan state.
- `Views/SpectrumView.swift` — per-band Canvas spectrum with hit testing.
- `Models/RFOverviewLayout.swift` / `Views/RFOverviewView.swift` — all-band RF
  overview: pure MHz geometry (spans, overlap regions, recommended-channel
  marker) tested in `Tests/RFOverviewLayoutTests.swift`, drawn as three band
  panels with click-to-select.
- `Views/AppTabBar.swift` — the shared tab strip (sections + items + selection)
  used by the Wi-Fi workspace's bottom tabs, LAN Scanner and survey planning.
- `Views/AppLayout.swift` — `appSheet`, `AppSheetHeader`, `AppColumnWidth` and
  `appTableSurface`: the shared sheet chrome, table column widths and table
  surface. New screens use these instead of local widths and paddings.
  `DesignToken.Spacing`/`Radius` cover all common insets and corners; see
  `docs/VISUAL_CHECK_2026-11.md` for the captured screens.
- `Views/HelpView.swift` — task-oriented Help window: six topics, each with one
  bundled screenshot (`Resources/help-*.png`) and steps, plus search. The RF
  overview (`Views/RFOverviewView.swift`) carries the chart's "What is this?"
  popover explaining bars, overlap shading and the recommended channel.
- `Views/GeneralSettingsPage.swift` — card-based General settings (appearance,
  startup/login item, Sparkle updates, menu bar, display, data, help).
- `Services/LaunchAtLoginController.swift` — `SMAppService` login item state.
- `Models/ClientAnalytics.swift` / `Views/Toolkit/ClientAnalyticsToolView.swift`
  — P1.3: advertised per-AP client counts plus optional captured client frames,
  vendor/probe mix and plain-language insights.
- `Models/SurveyGeo.swift` / `Services/CurrentLocationProvider.swift` /
  `Views/SurveyMapView.swift` — P1.9: GPX import/export, optional per-sample
  latitude/longitude, MapKit plotting and current-location tagging.
- `Models/OpenConnections.swift` / `Views/Toolkit/OpenConnectionsToolView.swift`
  — P1.8: parsed read-only `lsof` TCP inventory (process, PID, endpoints,
  state), filtering and per-process summary.
- `Models/SurveyPlanning.swift` / `Views/SurveyPlanningView.swift` — P1.4:
  free-space AP layout planning, coverage estimate and active-survey gap/next-
  target tracking.
- `Views/TableStyle.swift` — `appTableDensity()`: reads `LanFi.rowDensity` live
  and injects `appTableDensity`, `defaultMinListRowHeight` and `controlSize` so
  lists/tables follow Settings without a relaunch.
- `Views/Theme.swift` — the app's only design contract: `Theme.Spacing`,
  `.Radius`, `.Stroke`, `.Layout`, `.Toolbar`, `.Typography` (semantic fonts),
  `.Surface` (card/panel fills, borders, banner fills), `.Control` (control
  height, icon width, padding) and `.Palette` (semantic, band and quality
  colours). `DesignToken` and `AppPalette` are aliases, so no call site had to
  change and no value is written twice. The file also owns `.appCardSurface`,
  `.appPanelBorder` and `.appSectionLabel`.
- `Views/DesignSystem.swift` — the components that consume the theme:
  `AppCard`, `SectionLabel`, `StatusPill`, `StatTile` and `BandChip`. A screen
  that needs a card, a section header or a status pill uses one of these (or
  `.appCardSurface`) instead of drawing its own fill, radius, stroke and font.
- `Views/SignalHistoryView.swift` — Swift Charts signal history with cursor and a
  signal / noise / both mode. `Views/ChartStyle.swift` holds the shared axis,
  grid, cursor and tooltip tokens for every Swift Charts surface.
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
- `Views/Toolkit/` — the Network Toolkit, which is the app's main window:
  grouped custom sidebar, per-tool screens and the full Wi-Fi analyzer
  workspace.
- `CLI/MCPProtocol.swift`, `CLI/MCPToolkit.swift` — transport-free MCP
  JSON-RPC handler and the handler catalogue (scan analysis, client analytics,
  survey planning and open connections plus ping, traceroute, MTR, port scan,
  path check, DNS, propagation, WHOIS, GeoIP, TLS, subnet, interfaces, routes,
  LAN scan, iperf3, speed test, uptime, diagnostics, and spectrum CSV analysis).
  The handler lives in 73 lines; `CLI/MCPToolkit+{Scan,Probes,ServiceTools,
  Arguments,Encoding}.swift` hold the implementations. The advertised specs are
  `MCPToolRegistry` in `Models/MCPToolSpec.swift`, shared with the app and tests.
  Unit tested in `Tests/MCPProtocolTests.swift` and `Tests/ToolRoutingTests.swift`.
- `Models/ToolDescriptor.swift`, `Models/ToolRouting.swift` — the tool registry.
  A descriptor carries title/icon/section, `screen: ToolScreen` (the view
  route, shared by tabbed tools such as Sockets/Traffic) and `mcpTools` (the
  `MCPToolRegistry` names the screen exposes). Add a tool by adding one
  descriptor and one view case.
- `Models/DeviceShelfModels.swift`, `Services/DeviceShelfStore.swift`,
  `ViewModels/DeviceShelfViewModel.swift`, `Views/Toolkit/DeviceShelfView.swift`
  — the Device Shelf tab of the LAN Scanner: a persistent inventory (alias,
  type, ports, availability, latency samples, risk score, event history) stored
  in `~/Library/Application Support/LanFi/device-shelf.json`. Merge logic lives
  in `DeviceShelfMerger` and is unit tested in `Tests/DeviceShelfTests.swift`.
- `CLI/MCPServer.swift` — stdio transport (`lanfi-cli mcp`) for AI agents.
  Reads the live snapshot written by `Services/MCPSnapshotWriter.swift`
  (see `docs/mcp.md`).
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

Every key below is a case of `AppSettingsKey` (`Packages/LanFiCore`); never
spell a `LanFi.*` string at a call site. `AppSettings` is the canonical typed
model and `AppSettingsStore` writes the legacy keys as mirrors, so an
`@AppStorage` reader stays live. A save first re-reads the keys an older screen
still writes directly (monitor, capture, survey, reports, alerts, MCP, layout),
so those values cannot be rolled back; `importData` overwrites them on purpose.

- `WifiColumns_v4` — JSON `[ColumnDefinition]` (order/width/visibility/title).
- `LanFi.tabLayoutVersion` — one-time migration to the Insights-first tab layout.
- `RefreshIntervalSeconds` — scan interval.
- `LanFi.filterBand24|filterBand5|filterBand6` — band filters.
- `LanFi.minSignal`, `LanFi.removeAfter` — signal threshold and expiry.
- `LanFi.signalUnit`, `LanFi.highlightConnected` — display options.
- `LanFi.scan.dwellMilliseconds` — last passive/directed dwell per channel.
- `LanFi.menuBar.metric|style|unit` — menu-bar meter metric, label style and
  throughput unit (mirrored from `AppSettings.menuBar`).
- `LanFi.listeners.watch` — the Connections listener watcher toggle
  (`AppSettings.automation.listenerWatch`).
- `LanFi.descriptions.model` — opt-in on-device service descriptions
  (`AppSettings.automation.serviceDescriptions`).
- `LanFi.gatewayGuard.enabled` — gateway ARP / DNS integrity guard
  (`AppSettings.automation.gatewayGuard`).
- `LanFi.vpnGuard.enabled` — VPN state and leak indicators
  (`AppSettings.automation.vpnGuard`).
- `LanFi.linkAutomation.enabled` — Wi-Fi off while Ethernet is up
  (`AppSettings.automation.linkAutomation`, off by default).
- `LanFi.connectivity.enabled|interval|primaryURL|fallbackURL` and
  `LanFi.connectivity.notify.offline|captive|restored` — the connectivity
  watchdog (`AppSettings.connectivity`); quiet hours are read from
  `LanFi.monitor.alerts`.
- `LanFi.historyChart.mode` — signal / noise / both for the history chart.
- `LanFi.hasCompletedFirstRun` — the first-run screen is shown once.
- `LanFi.settings.section` — the last selected sidebar section in Settings.
- `LanFi.sortKey`, `LanFi.sortAscending` — table sort.
- `LanFi.showInspector`, `LanFi.bottomTab` — layout
- `LanFi.toolkit.selection`, `LanFi.toolkit.sidebarWidth` — toolkit selection
  and sidebar width.
- `LanFi.inspectorWidth`, `LanFi.bottomPanelHeight` — analyzer panel geometry.
  (`0` Overview, `1` Profile, `3` Raw Data, `4` Spectrum, `5` History,
  `7` Capture, `8` Monitor, `9` All Bands; `2` Interfaces and `6` Diagnostics
  were retired into the Network Toolkit and are migrated to Overview).
  Fresh installs default to `9`; stored values are never rewritten.
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
  sample coordinates, so window resizing does not move points. Samples may also
  carry optional GPS coordinates, and the project stores an optional GPX track.
- Survey Planning is pure (`SurveyPlanner`, `ActiveSurveyAdvisor`): free-space
  radius from tx power/target RSSI, grid AP placement, coverage estimate and a
  sample-gap grid with the next target location.

## Vendor database

`Resources/oui` is generated from the IEEE MA-L/MA-M/MA-S registries and the
Wireshark `manuf` file. Prefixes are 6, 7 or 9 hex characters and the lookup
uses the longest match. Refresh it with:

```bash
python3 scripts/update_oui.py
```

## Network Toolkit

The Network Toolkit is the app's main window (`WindowGroup(id: "main")`).
`Layout → Wi-Fi Analyzer` (⇧⌘T) selects its Wi-Fi workspace. The toolkit has a
custom grouped sidebar (resizable, width persisted), no Recent section, and the
last selected tool is restored from `LanFi.toolkit.selection`. The Wi-Fi
Analyzer tool embeds the full analyzer (`MainTableView(embedded: true)`):
table, top-row filters, inspector and bottom panels. Filters used to be a
collapsible sidebar; they now live in the top filter bar, and controls that
narrow the list tint themselves. Capture, Spectrum and History stay in the
bottom panel tabs; Hardware Spectrum, offline capture analysis and Remote
Sensors open as full-size sheets from the toolbar's Wi-Fi Tools menu because
they depend on analyzer charts and need the extra room.
`ToolboxTool` owns the catalogue, `isAvailable` marks wired screens, and planned
rows stay visible with a "Planned" badge. Advanced Tools embeds the
`ToolConsoleView` in the Network Tools section; there is no separate Tool
window.

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

## Settings and dependencies

`Packages/LanFiCore` holds the typed settings layer and builds in the Swift 6
language mode:

- `AppSettings` — Codable sections (appearance, scan, alerts, monitor, capture,
  survey, reports, MCP, automation, display, interface, layout). New sections
decode with defaults, so an older settings file still loads.
- `AppSettingsKey` — the one catalogue of persisted keys.
- `AppSettingsStore` — load/migrate/save/export/import, legacy mirrors, and
  injected `Clock`, `SettingsStorage`, `NotificationPosting` and `FileStoring`.
- `Dependencies.swift` — `Clock`/`SystemClock`/`FixedClock`, the storage and
  notification protocols, and `FileStore`.

The app uses the same seam style: `WiFiScanning` is injected into
`AnalyzerViewModel`, and `MonitorViewModel` takes a `Clock` and any
`MonitorNotifying`; `UserNotifying` already covered LAN guard notifications.

## Automation and release

- `scripts/release_artifacts.sh` builds a drag-to-install DMG: a read-write
  image is mounted, an AppleScript places `LanFi.app`, an Applications alias and
  the two bilingual read-me pages (`packaging/dmg/read-me-en.html`,
  `read-me-ru.html`, Gatekeeper bypass steps), then it is converted to UDZO.
  The read-mes are never embedded in the app bundle.
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
  always resolves to the newest build. The same unversioned asset names
  (`LanFi.dmg`, `LanFi.zip`, `LanFi-CLI.zip`) live inside each tagged release,
  so pinned URLs stay immutable without a second set of versioned files.
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
- No telemetry. The only outbound requests are the connectivity watchdog's
  captive-portal probes (on by default, toggleable), the opt-in OUI update and
  tools the user runs; none upload data. Location is only for SSID/BSSID
  visibility.
- Prefer semantic colors; charts must remain legible in dark and light mode.
