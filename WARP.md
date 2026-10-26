# WARP.md — working on WiFA

This file orients coding agents and contributors. See also `CONTRIBUTING.md`.

## Project overview

WiFA is a native macOS 13+ Wi‑Fi analyzer: SwiftUI shell, an AppKit
`NSTableView` bridge for the network list, Swift Charts for history, and a
Canvas-based spectrum view. Scanning uses only public CoreWLAN APIs. No
analytics, networking, accounts or third-party SDKs.

## Essential commands

```bash
xcodegen generate                 # project.yml is the source of truth
open WiFA.xcodeproj               # develop/run
./build.sh                        # universal Release app + ad-hoc signature

xcodebuild test \
  -project WiFA.xcodeproj \
  -scheme WiFA \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

./scripts/lint.sh
./scripts/format.sh
```

Outputs:
- Debug: `build/DerivedData/Build/Products/Debug/WiFA.app`
- Release: `build/WiFA-Universal/WiFA.app`

If you add/move/delete files, run `xcodegen generate` and commit the regenerated
`WiFA.xcodeproj/project.pbxproj` and `Info.plist`.

## Architecture

- `WifiAnalyzerApp.swift` — `@main`, single `AnalyzerViewModel` and
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
- `Views/SpectrumView.swift` — per-band Canvas spectrum with hit testing.
- `Views/SignalHistoryView.swift` — Swift Charts signal history with cursor.
- `Views/RawDataView.swift` — expandable IE table.
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
- `Wifa.tabLayoutVersion` — one-time migration to the Insights-first tab layout.
- `RefreshIntervalSeconds` — scan interval.
- `Wifa.filterBand24|filterBand5|filterBand6` — band filters.
- `Wifa.minSignal`, `Wifa.removeAfter` — signal threshold and expiry.
- `Wifa.signalUnit`, `Wifa.highlightConnected` — display options.
- `Wifa.sortKey`, `Wifa.sortAscending` — table sort.
- `Wifa.showSidebar`, `Wifa.showInspector`, `Wifa.bottomTab` — layout
  (`0` Insights, `1` Spectrum, `2` History, `3` Raw Data).
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

## Vendor database

`Resources/oui` is generated from the IEEE MA-L/MA-M/MA-S registries and the
Wireshark `manuf` file. Prefixes are 6, 7 or 9 hex characters and the lookup
uses the longest match. Refresh it with:

```bash
python3 scripts/update_oui.py
```

## Testing

`WiFATests` compiles `NetworkModel`, `NetworkAnalyzer`,
`InformationElementParser` and `OUIParser` directly (no app host, no
CoreWLAN), so tests run headless. Add pure-logic tests for scoring, overlap,
recommendations, parsing and export DTOs. Avoid UI tests that require Location
permission.

## Automation and release

- `scripts/autopush.sh` commits/pushes meaningful changes; `--install-hook`
  installs a `post-commit` hook. It refuses credentials/oversized files and
  rebases on non-fast-forward pushes.
- CI (`.github/workflows/ci.yml`) runs swift-format lint, XCTest and a universal
  Release build on macOS 15.
- Release (`.github/workflows/release.yml`) is triggered by `v*` tags: verifies
  the tag against `project.yml`, tests, builds, packages ZIP + DMG + SHA-256,
  and publishes notes from `CHANGELOG.md`.
- `./release.sh X.Y.Z` updates `project.yml`, regenerates the project, commits,
  pushes and tags.

## Constraints

- Public CoreWLAN only; no private APIs, no `airport` CLI parsing.
- Keep scanning/parsing off the main thread; UI state stays `@MainActor`.
- Pure analysis belongs in `NetworkAnalyzer`/`InformationElementParser` with
  tests.
- No telemetry or network calls. Location is only for SSID/BSSID visibility.
- Prefer semantic colors; charts must remain legible in dark and light mode.
