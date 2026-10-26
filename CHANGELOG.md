# Changelog

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
