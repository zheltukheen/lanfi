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

**Behind paid tools**
- Notarized builds + reliable auto-updates (Sparkle) and Homebrew distribution.
- SSID/AP grouping, column profiles, multi-select and saved sessions.
- PCAP/PCAPNG export and offline pcap analysis.
- Wi-Fi 7 MLO link details, 320 MHz/EHT decoding, 802.11-2024 regulatory info.
- AP-name detection from vendor IEs (Aruba, Ubiquiti, Mist, Ruckus, …).
- Remote sensors, external adapters, heatmaps/site surveys, spectrum hardware.
- Full localization, VoiceOver coverage, Windows parity (out of scope for now).
- In-app vendor database updates and crash diagnostics.

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
- [x] Grouping, annotations and saved sessions (column profiles pending)
- [~] PCAP export (synthetic beacons; live capture pending)
- [~] AP names/annotations; MLO/EHT details pending
- [~] Russian primary UI + VoiceOver summaries (full localization pending)
- [~] Survey-lite heatmap (remote sensors and interpolation pending)

LanFi covers the first three. The roadmap above closes the rest in value order;
1.4 and 1.5 are the minimum for “commercial parity minus surveys”.

## Non-goals

- Cloud accounts or mandatory telemetry.
- Predictive enterprise Wi-Fi design (Ekahau/Hamina class) in the near term.
- Windows/Linux ports before macOS distribution is trustworthy.
