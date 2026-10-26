# Changelog

## 1.5.0 — 2026-10-26

### Added
- **Protocols tab** with six block-oriented views per network: radio/PHY, security, roaming, spectrum, network format and vendor capabilities, plus an all-network coverage summary.
- **Network diagnostics** engine and tab: Wi-Fi radio/link, signal, security, IPv4/IPv6, gateway ICMP, DNS resolution, captive-portal/HTTPS check and public latency, with automatic 60-second monitoring and report copying.
- **Editable annotations** per BSSID: alias, comma-separated tags and free-form notes, persisted locally and reflected in the network name/annotations columns.
- **Grouping** by SSID, band, vendor or security, with group summaries and preservation of the current sort order.
- **Saved scan sessions**: save locally, reopen without scanning, pause live refresh and resume when ready.
- **Synthetic PCAP export** of rewritten 802.11 beacon frames for offline inspection (clearly labelled as synthetic; live frame capture is still on the roadmap).
- **Site Survey window** with floor-plan import, click-to-record RSSI samples and a heatmap overlay.
- **Sparkle 2 auto-updates** with a signed appcast, plus a Homebrew cask and cask update automation.
- Russian localization for the primary navigation, columns, Insights, Protocols and Diagnostics surfaces.
- VoiceOver summaries for signal history, spectrum, channel occupancy and survey heatmaps.

### Changed
- Bottom tabs are now Insights, Spectrum, History, Raw Data, Protocols, Diagnostics.
- The command bar includes Data → Save/Open Session and Export PCAP, Survey → Open Site Survey, and Diagnostics → Run/Monitor.
- Network details now include editable label and notes.
- Build actions were updated to checkout@v7, upload-artifact@v7 and action-gh-release@v3 after review.

### Fixed
- Group rows now render their headers and keep network selection/row indexing correct.
- Annotation edits immediately refresh the table and persist with a debounce.
- Survey projects store floor plans in per-project directories and reload the latest project.
- Session timestamps retain millisecond precision so recent sessions sort correctly.

### Engineering
- New pure models/services: `ProtocolProfile`, `ProtocolAnalyzer`, `DiagnosticsModel`, `DiagnosticsEngine`, `NetworkGrouping`, `NetworkAnnotation`, `ScanSession`, `PcapExporter`, `Survey`.
- Expanded test suite to 63 tests covering protocol blocks, diagnostics scoring/parsing, grouping, annotations, sessions, survey persistence and PCAP headers.
- Sparkle private key is stored as a GitHub Actions secret; release builds generate and attach `appcast.xml`.


## 1.4.0 — 2026-10-26

### Added
- **Insights is now the first and default tab**, with a one-time migration for existing layouts.
- **Commercial gap analysis and prioritised roadmap** in `docs/COMMERCIAL_GAP.md`, based on current WiFi Explorer Pro, NetSpot, inSSIDer, Acrylic and survey tools.
- **Full column coverage tests** for every declared column, including minimal/unknown networks and sort comparators.
- **Vendor database expanded to 58,407 prefixes** from IEEE MA-L, MA-M, MA-S and the Wireshark manufacturer registry, with longest-prefix lookup for 24/28/36-bit assignments.
- **Filtered empty state** explaining that filters hide results, with a Clear Filters action.
- All table columns now go through a pure, testable `NetworkColumnFormatter`; column metadata lives in `Models/ColumnCatalog.swift`.

### Changed
- Table rows are taller (30 pt) and raw-data rows use 28 pt.
- Vendor fallback list now contains verified IEEE names and no fabricated mappings.
- Vendor update script can ingest multiple IEEE/Wireshark sources and reports prefix coverage.
- Tab shortcuts and menu order are now Insights, Spectrum, History, Raw Data (⌘1–⌘4).

### Fixed
- Column resizing no longer fights SwiftUI updates: widths are committed after a short debounce and ignored while a divider is dragged.
- “No networks found” is replaced by “No matching networks” when only filters/search hide the results.
- Invalid MAC-like strings no longer produce bogus hex prefixes in vendor lookup.
- App builds with Xcode 16.4 / the macOS 15 SDK while still detecting Wi-Fi 7 at runtime (raw `CWPHYMode` value).

### Engineering
- Added tests for the longest-prefix vendor lookup, column metadata, all 43 column renderers and all column comparators.
- CI remains green on macOS 15; the Dependabot actions branch was rebased and now passes.


## 1.3.0 — 2026-10-26

### Added
- **Insights panel** with 0–100 quality scores, ranked channel recommendations per band, a grouped security audit, and channel-occupancy charts.
- **Quality and congestion columns** plus a quality inspector with signal, SNR, congestion, security, overlap counts and actionable issues.
- **Channel recommendations** weighted by overlap, signal strength and reported channel utilization for 2.4 GHz, 5 GHz and 6 GHz, including DFS labelling.
- **Security audit** for open/WEP/legacy WPA networks, WPS, PMF (802.11w) and weak-signal/congestion warnings.
- **Per-band spectrum view** with a band selector and correct 2.4/5/6 GHz channel labelling.
- **JSON export** with metrics, recommendations and issues; CSV export now uses RFC 4180 line endings and a UTF-8 BOM.
- **Menu bar extra** showing connection, quality, recommended 5 GHz channel and quick actions.
- **Wi-Fi 7 (802.11be)** generation detection with one-stream rate estimates.
- **Location permission onboarding**, empty-scan state and a live status bar.
- **Automatic push automation** (`scripts/autopush.sh`) with a post-commit hook, debounced watch mode, safety checks and retries.
- Unit tests for scoring, overlap math, recommendations, security findings, RSN/WPS parsing and IE decoding.
- CI test/lint/build workflow, release DMG packaging, Dependabot, issue/PR templates and a privacy manifest.
- MIT license, privacy policy, security policy, contributing guide and code of conduct.

### Changed
- Default column layout now starts with Network Name, Signal, Quality, Band, Channel, Width and Security; advanced fields remain available from the column menu.
- Signal sorting defaults to strongest-first.
- UI, filter and panel preferences persist across launches.
- The default bottom panel is shorter so the network table gets more room.
- Spectrum and signal-history charts now follow light/dark appearance and the spectrum view switches to the selected network's band.
- The project is generated from `project.yml` with a shared scheme and a test target.
- The Xcode project now enables hardened runtime and uses a stable bundle identifier (`ru.zheltukheen.WiFA`).

### Fixed
- Sorting no longer has undefined ordering when two rows compare equal.
- The header context menu no longer exposes a misleading “Show Text Only” action; it now toggles connected-network highlighting.
- “Align Text” and “Rename Column” context-menu commands now update the correct column.
- CSV export reports write errors instead of silently failing.
- WPS/PMF data from beacon information elements is surfaced in security scoring.
- The duplicate ~700 KB `oui.csv` resource was removed and randomized MACs are labelled correctly.
- The parser was split out of the CoreWLAN scanner into a testable `InformationElementParser`.

### Engineering
- Added `swift-format` configuration and formatted the Swift sources.
- CI runs `swift-format lint`, XCTest and a universal Release build on macOS 15.
- Release workflow verifies the tag against `project.yml`, runs tests, builds a universal app, packages ZIP + DMG + SHA-256, and publishes release notes from this changelog.
- Build scripts fail fast, produce an ad-hoc signed universal app, and print the resulting architectures/version.


## 1.2.1 — 2026-02-08
- Added a new AppIcon asset catalog with a redesigned macOS icon set.
- Updated About panel credits to include author name.
- Updated build resources to include the asset catalog.

## 1.2.0 — 2026-02-07
- Added macOS menu bar commands for scanning, filters, display controls, panels, and export.
- Introduced shared table cell components and applied consistent header padding/alignment.
- Rebuilt Raw Data into a table that expands by inserting detail rows (Element ID, Length, decoded fields).
- Expanded Information Element decoding, including HE/RSN/WPS details and vendor-specific parsing.
- Improved sidebar layout, tab labels, and panel controls.
- Updated About panel metadata and bumped version/build.
