# Commercial gap analysis & roadmap

_Last researched: 2026-10-26. Prices and feature sets change; verify before
quoting externally._

LanFi already goes beyond most free analyzers on **interpretation**: a 0–100
quality score, ranked channel recommendations, and a WPA3/OWE/PMF/WPS security
audit with remediation. The remaining gap to paid desktop tools is mostly
**workflow, distribution and survey features**, not raw scanning.

## Competitive landscape

| Product | Positioning | Notable capabilities | Typical price |
| --- | --- | --- | --- |
| **LanFi** | Free, open-source, privacy-first macOS analyzer | Quality/congestion scores, ranked 2.4/5/6 GHz channels, security audit, IE decoding, CSV/JSON, menu bar, 58k-prefix OUI DB | Free (MIT) |
| **WiFi Explorer Pro 3** (macOS) | Prosumer/IT analyzer | 950+ fields, grouping and column profiles, remote sensors (SSH/WLAN Pi), PCAP/PCAPNG, hardware spectrum, MLO/Wi-Fi 7 details, AP-name detection, vendor DB updates, 5 languages, notarized | ~$100–150 one-time |
| **WiFi Explorer** (macOS) | Mainstream Mac analyzer | Fast scan, filters, details, 6 GHz, clean native UI, notarized | ~$20 one-time |
| **NetSpot** | Heatmaps/site surveys | Floor-plan import, walking surveys, heatmaps, reports | Free tier; ~$19/mo or ~$179 one-time |
| **inSSIDer** | Live troubleshooting | Real-time graphs, saved scans, packet capture, Wi-Fi 6E/7 | Free Lite; ~$25/year |
| **Acrylic Wi-Fi Home** | Free Windows analyzer | Channel graphs, link rate, security, OUI lookup | Free; Pro ~$99 |
| **Homedale** | Portable utility | Lightweight scan, channel graphs, GPS, CLI in paid tier | Free/paid |
| **Ekahau AI Pro** | Enterprise survey | Predictive design, passive/active surveys, Sidekick hardware | Enterprise quote |
| **Apple Wireless Diagnostics** | Built-in | Scan, performance, sniffer, basic recommendations | Free |

Sources: [WiFi Explorer Pro 3](https://www.intuitibits.com/products/wifiexplorerpro3/),
[WiFi Explorer Pro release notes](https://www.intuitibits.com/release-notes/wifiexplorerpro-windows/),
[NetSpot](https://www.netspotapp.com/), [inSSIDer](https://www.metageek.com/inssider/),
[Acrylic Wi-Fi](https://www.acrylicwifi.com/), [Homedale](https://www.the-sz.com/products/homedale/),
[Ekahau](https://www.ookla.com/ekahau), [Unstore 2026 comparison](https://unstore.io/discover/best-wifi-analyzer-apps-desktop).

## Where LanFi stands

**Ahead of the market**
- Graded security findings (critical/warning/info) with remediation text.
- Explainable quality and channel-overlap scoring, not only raw fields.
- Ranked channel recommendations for 2.4, 5 and 6 GHz including DFS notes.
- Open source, local-only, no telemetry or account.
- One-click CSV and JSON with metrics and recommendations.

**At parity**
- Native CoreWLAN scan, 6 GHz/Wi-Fi 7 generation detection, IE decoder,
  spectrum/history charts, filters, configurable columns, menu bar extra,
  universal build, tests/CI.

**Behind paid tools / external**
- Notarized builds (only an Apple Development identity is available; no Apple
  Developer Program account).
- External USB Wi-Fi adapter measurement path beyond interfaces exposed by
  CoreWLAN.
- Hardware spectrum analyzer integration (WLAN Pi, Wi-Spy, etc.).
- Full per-link MLO BSSID sets (AP MLD and link IDs are decoded; BSSID sets
  need a dedicated monitor-capture parser).
- Manual VoiceOver audit of every remaining screen (chart descriptors and key
  controls are covered).

## Delivered in 2.5.2

- Clickable filter section headers and a designed sort popover.
- Colored 2.4/5/6 GHz + Wi-Fi 7 chips in the toolbar; Wi-Fi 7 filter
  persistence and filter-profile support.
- Multi-select comparison grid and bulk alias/notes editing.
- Reliable live-capture shutdown and clear wrong-link-type diagnostics.

## Delivered in 2.3

- Dynamic technical localization (SSID-safe phrase catalog).
- Additional VoiceOver labels and continued accessibility polish.
- 2.3 release with app/CLI/DMG assets and signed appcast.

## Delivered in 2.1

- Multi-Link extension element decoding (Basic / Probe / Reconfiguration).
- 2.1 release assets: app, CLI, DMG, checksums, signed appcast.

## Delivered in 2.0

- Offline pcap/pcapng analysis and PCAPNG export.
- Multi-select and bulk export, menu-bar alerts, filter profile import/export.
- CLI (`lanfi-cli`), deep links and URL scheme.
- Vendor database updater and custom OUI overrides.
- Survey floor projects and PDF reports; throughput test.
- Remote-sensor polling, diagnostics bundles and local crash logs.
- Conditional Developer ID/notarization release pipeline and smoke tests.

## Delivered in 1.9

- Persisted diagnostics history (last 12 reports) with restore/clear.
- AXChartDescriptor VoiceOver audio graphs for signal history and channel occupancy.
- Combined accessibility cards for protocol blocks and interfaces.
- Expanded Russian localization for remaining static UI.

## Delivered in 1.8

- SSH-based **remote sensors** with saved hosts and a results table.

## Delivered in 1.7

- First-class **Interfaces** analysis for every BSD interface.
- **Live PCAP** capture through tcpdump/BPF with administrator authorization.
- **IDW survey interpolation** and wall attenuation with a wall editor.
- **Column profiles**, AP-name detection and a Wi-Fi 7/EHT/MLO block.
- Notarization tooling and distribution documentation.

## Delivered in 1.6

- Renamed the product to **LanFi** (bundle id retained for update continuity).
- Reorganized the bottom panel into Overview/RF/Network/Troubleshoot categories.
- Made Insights scope explicit ("all visible networks" + connected network).
- Clarified Protocols as selected-network analysis; fixed card heights and order.
- New bold LanFi icon and higher default bottom panel.

## Delivered in 1.5

- Protocol blocks, all-network protocol coverage and capability decoding.
- Diagnostics engine + tab with 60-second monitoring.
- Annotations, grouping by SSID/band/vendor/security and saved sessions.
- Sparkle 2 signed auto-updates, Homebrew cask and cask automation.
- Synthetic beacon PCAP export.
- Survey-lite floor plan + RSSI heatmap.
- Russian localization of primary surfaces and VoiceOver chart summaries.
- Reviewed and merged the Dependabot GitHub Actions update after a green CI run.

## Prioritised roadmap

### 1.4 — Trust and distribution (highest impact, smallest scope)

| Item | Why | Effort |
| --- | --- | --- |
| Developer ID signing + `notarytool` + stapled DMG | Removes Gatekeeper friction; required for a credible download | M |
| Sparkle 2 appcast + EdDSA signatures | Users receive security fixes without reinstalling | M |
| Homebrew cask | Standard macOS install path; discoverability | S |
| Opt-in crash reports + diagnostics export | Fix field crashes without violating privacy | S |
| Release smoke test on a clean macOS VM | Catches launch/permission regressions before publish | S |

**Exit criteria:** download → launch has no Gatekeeper workaround; an update can
be delivered and verified end-to-end.

### 1.5 — Analyzer parity

| Item | Why | Effort |
| --- | --- | --- |
| Grouping by SSID / AP / band with summary rows | Core workflow in WiFi Explorer Pro; makes large scans readable | M |
| Column profiles (save/switch layouts) | Table stakes for IT users with different tasks | S |
| Saved scan sessions + timeline snapshots | Compare before/after; diagnose intermittent issues | M |
| PCAP/PCAPNG export | Offline analysis in Wireshark; expected by professionals | M |
| AP-name detection from vendor IEs | Turns opaque BSSIDs into “Lobby AP”, “Office-3” | M |
| MLO + 320 MHz/EHT/Extended BSS Load decoding | Wi-Fi 7 correctness; commercial tools already ship it | M |
| In-app vendor DB updater + custom OUI overrides | Wi-Fi vendor data changes weekly; no app release needed | S |

**Exit criteria:** a consultant can group, annotate, save, export and hand off a
scan without leaving LanFi.

### 1.6 — Workflow and reach

| Item | Why | Effort |
| --- | --- | --- |
| Remote sensors (SSH/WLAN Pi) | Multi-point surveys; Pro differentiator | L |
| Menu bar alerts (weak signal, open network, channel change) | Passive monitoring between scans | S |
| Filter/profile import-export and URL scheme | Automation and team sharing | S |
| English + Russian localization, VoiceOver pass, high contrast | Reach and accessibility | M |
| CLI/JSON automation for CI and support scripts | Power-user integration | M |

### 2.0 — Survey

| Item | Why | Effort |
| --- | --- | --- |
| Floor-plan import + walk survey + heatmaps | NetSpot's core value; only path to survey budgets | L |
| External USB adapter selection | Consistent measurements, 6 GHz coverage | M |
| Spectrum hardware integration (WLAN Pi etc.) | Pro/enterprise credibility | L |
| Throughput/latency diagnostics (ping + local iperf) | Connects RF findings to user experience | M |

## Definition of “industry standard”

A credible commercial competitor in 2026 needs all of the following:

- [x] Native scan, 2.4/5/6 GHz, Wi-Fi 6E/7 generation detection
- [x] Quality/interference/channel guidance and security posture
- [x] CSV/JSON export, copy, search, filters, configurable columns
- [x] Signed auto-updating distribution (Sparkle); notarization still pending
- [x] Grouping, annotations, saved sessions and column profiles
- [x] PCAP/PCAPNG export and offline capture analysis
- [~] AP names, EHT/320 MHz and Multi-Link element decoding (per-link BSSID sets pending)
- [x] Russian UI and dynamic technical localization; VoiceOver chart descriptors
- [x] IDW survey heatmap with walls, PDF reports and SSH remote sensors

LanFi covers the first three. The roadmap above closes the rest in value order;
1.4 and 1.5 are the minimum for “commercial parity minus surveys”.

## Non-goals

- Cloud accounts or mandatory telemetry.
- Predictive enterprise Wi-Fi design (Ekahau/Hamina class) in the near term.
- Windows/Linux ports before macOS distribution is trustworthy.
