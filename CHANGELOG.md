# Changelog

## 2.5.3 — 2026-10-26

### Added
- Dedicated branded **About LanFi** window with app icon, version, feature
  summary, links and ad-hoc signing disclosure.
- Searchable **LanFi Help** window with 10 topics (English/Russian), keyboard
  shortcut reference and README/issue links.
- Help menu entry (⌘?) and About menu entry now open these windows.

### Changed
- Renamed the custom Display menu to Layout to avoid colliding with the
  system-localized View menu.
- Help sidebar width increased for long topic names.


## 2.5.2 — 2026-10-26

### Changed
- Sidebar section headers now toggle by clicking the entire row, not only the
  disclosure arrow.
- Sort picker replaced by a larger custom popover with hover states and
  checkmarks.
- Band filters are capsule chips with distinct colors; added the Wi-Fi 7
  (802.11be) chip alongside 2.4/5/6 GHz.
- Wi-Fi 7 filter persists in preferences and filter profiles.


## 2.5.1 — 2026-10-26

### Fixed
- Wi-Fi monitor captures that produce only a 24-byte header now fail with a
  clear explanation instead of surfacing tcpdump’s “listening” log as an error.
- Non-802.11 pcap/pcapng files (RAW IP/Ethernet) are rejected with the detected
  link type and a hint to select a monitor interface.
- Sidebar filter/sort controls redesigned into cards with hover states, count
  badges, checkmarks and a dedicated sort direction control.
- Duplicate View menu removed by renaming the custom menu to Display.


## 2.5.0 — 2026-10-26

### Added
- Multi-select comparison grid (signal/channel/quality) and bulk alias/notes
  editing for every selected network.

### Changed
- Version 2.5.0 (build 22).


## 2.4.1 — 2026-10-26

### Fixed
- Live capture now records the tcpdump PID, sends SIGTERM, waits with a
  bounded loop, then SIGKILL, and only then reaps the process. This replaces
  the SIGINT-only path that could leave a root tcpdump writing for hours.
- Unique output/error paths and the capture lock remain in place.


## 2.4.0 — 2026-10-26

### Fixed
- Live capture now uses a unique output/error file per run, serializes captures,
  escalates INT→TERM→KILL and waits for tcpdump, so a capture actually stops and
  the next run cannot write into the previous file.
- Captured files can be opened directly in the offline analyzer.

### Changed
- Overview replaces Insights; Profile replaces Protocols; NETWORK sits directly
  after OVERVIEW, before RF.
- Inactive/unused interfaces are collapsed under “Inactive interfaces”.
- Signal history dynamically scales the RSSI range with padding.
- Diagnostics now has a health score, category grouping, SNR/IPv6 checks and
  actionable recommendations.
- Top menus consolidated into Scan, View, Tools and Data.
- Settings is now a tabbed app window: General, Alerts, Wi-Fi, Vendors,
  Diagnostics; includes ad-hoc/notarization explanation, update check, crash
  logs and support bundle export.
- Version 2.4.0 (build 20).


## 2.3.0 — 2026-10-26

### Added
- Dynamic technical localization for generated protocol/diagnostic/interface
  values using an SSID-safe phrase catalog.
- Additional VoiceOver labels on icon-only controls.

### Changed
- Version 2.3.0 (build 19); 108 tests.


## 2.2.0 — 2026-10-26

### Added
- Per-STA Multi-Link profile decoding: AP MLD address and per-link IDs.
- Accessibility labels on icon-only toolbar, diagnostics, settings and remote
  sensor controls; localized protocol detail/interface values.

### Changed
- Version 2.2.0 (build 18); 106 tests.


## 2.1.0 — 2026-10-26

### Added
- Decode the IEEE 802.11be Multi-Link extension element (Basic / Probe /
  Reconfiguration control types), in addition to EHT Operation/Capabilities and
  320 MHz detection. Full per-link BSSID sets still require offline capture.


## 2.0.0 — 2026-10-26

### Added
- **Offline capture analysis** for pcap and pcapng (radiotap or bare 802.11),
  with beacon/probe-response SSID, BSSID, channel, RSSI, security and EHT flags.
- **PCAPNG export** alongside classic pcap.
- **Multi-select** table with bulk copy and selected CSV/JSON export.
- **CLI** `lanfi-cli` with `summary`, `protocols`, `pcap` and JSON output;
  built and smoke-tested in CI/release.
- **Deep links** (`lanfi://tab/...`, `lanfi://search?q=...`,
  `lanfi://diagnostics/run`).
- **Filter profile import/export**.
- **Menu-bar alerts** for weak signal, open networks and connected-channel
  change, with Settings toggles.
- **Vendor database updater** (Wireshark manuf) and custom OUI overrides.
- **Survey floor projects**, PDF report export and IDW heatmap in the report.
- **Throughput test** through Apple `networkQuality`.
- **Remote-sensor auto-refresh** every 60 seconds.
- **Diagnostics bundle export** with report/history/interfaces/system info and
  recent local crash logs; local-only uncaught-exception logging.
- **Notarized release pipeline**: conditional Developer ID import, app/DMG
  notarization, headless release smoke test, CI smoke test.
- EHT Operation/Capabilities decoding and 320 MHz detection from IEs.
- Signature/accessibility polish: reduce-motion support, high-contrast card
  borders, chart descriptors and selected-tab VoiceOver trait.

### Changed
- Wi-Fi interface can be selected in Settings (external adapters exposed by
  macOS/CoreWLAN).
- Release uploads a `LanFi-CLI-<version>.zip` asset.
- Version 2.0.0 (build 16).

## 1.9.0 — 2026-10-26

### Added
- Diagnostics history is persisted across launches (last 12 reports); history
  capsules can restore a report and history can be cleared.
- VoiceOver chart descriptors for signal history and channel occupancy, plus
  combined accessibility cards for protocol blocks and interfaces.

### Changed
- Expanded Russian localization for remaining static UI: diagnostics, panels,
  filters, commands, profiles, empty states and status labels.
- Homebrew tap now points at the main repository, so every cask update is
  immediately installable via
  `brew tap zheltukheen/lanfi https://github.com/zheltukheen/wifa`.


## 1.8.0 — 2026-10-26

### Added
- **Remote sensors over SSH.** Save sensors, run `system_profiler
  SPAirPortDataType -json` on another Mac, and inspect its visible networks
  (SSID, band, channel, width, RSSI, SNR, PHY, security). Host/user input is
  validated against option injection; key-based login is required.
- Local Network usage description and Russian strings for the remote UI.

### Changed
- Remote sensor results are deduplicated and displayed in a dedicated sheet
  under **Data → Remote Sensors…**.


## 1.7.0 — 2026-10-26

### Added
- **Interfaces analysis for every BSD network interface on the Mac.** Physical,
  virtual, VPN, bridge, AWDL, cellular and loopback interfaces are enumerated
  with addresses, MTU, link speed, MAC, traffic counters, primary route, DNS
  and Wi-Fi association details. Live auto-refresh and copy-to-clipboard.
- **Live PCAP capture** via macOS `tcpdump`/BPF, with interface, duration,
  monitor-mode/radiotap option and a one-off administrator authorization.
  Synthetic beacon export remains available.
- **Survey interpolation and walls.** Inverse-distance-weighted heatmap replaces
  radial blobs; two-click wall drawing attenuates samples that cross a wall.
  Walls persist with the survey project and old projects decode unchanged.
- **Column profiles.** Save, apply, reset and persist named column layouts.
- **AP name detection** from printable vendor-specific IE payloads, shown in the
  AP Name column and protocol vendor block.
- **Wi-Fi 7 / MLO protocol block** with EHT IE count, 320 MHz visibility and an
  explicit note where CoreWLAN does not expose MLO link sets.
- **Developer ID / notarization tooling** (`scripts/notarize.sh`,
  `docs/DISTRIBUTION.md`) and `CODESIGN_IDENTITY` support in `build.sh`.
- Russian localizations for the new interface, capture, survey and protocol
  labels.

### Changed
- Bottom panel NETWORK category now contains Protocols, Interfaces and Raw Data.
- Tab layout migrates the 1.6 order to the new seven-tab order.
- Protocol analysis now has seven ordered blocks.
- The survey status moved into the map overlay so the toolbar fits at 900 pt.


## 1.6.0 — 2026-10-26

### Changed
- **Renamed the app from WiFA to LanFi.** The product, executable, Xcode project, scheme, cask, DMG/ZIP names, menus, About panel, appcast and documentation now use the LanFi brand. The internal bundle identifier remains `ru.zheltukheen.WiFA` so existing preferences, Location permission and Sparkle updates continue to work.
- **New bold app icon** (radar/Wi-Fi mark with an L monogram) across Dock, Finder, About panel and release bundles.
- **Bottom panel is taller** (460 pt by default, capped to 60% of the window) and tabs are grouped into Overview, RF, Network and Troubleshoot categories.
- **Insights scope is explicit**: a banner states that insights cover all visible networks and shows the currently connected network.
- **Protocols is explicitly scoped to the selected network**, with a six-block order (radio, security, spectrum, roaming, format, vendor), numbered cards and a fixed card height so blocks no longer jump in size.
- Localized bottom-panel categories and new scope labels; migrated annotations, sessions and surveys from the old `WiFA` Application Support directory.

### Fixed
- Tab layout migration maps the 1.5 order (Raw Data/Protocols) to the new order.
- Protocol cards with little advertised information keep the same size as full cards.
- App icon is now included from the asset catalog in every build (Dock, Finder, About).


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
