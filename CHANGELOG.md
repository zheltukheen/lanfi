# Changelog

## 5.1.0 — 2026-11-13

### Added
- **Faster LAN discovery.** The scanner now overlaps ARP nudging, an ICMP
  sweep, TCP probes, Bonjour, SSDP/UPnP and reverse DNS, with shorter
  timeouts and higher concurrency. Devices report advertised names, models,
  services and guessed roles instead of bare addresses.
- **Device Shelf enrichment.** The shelf inspector shows advertised services,
  type, vendor, hostname, model, latency trend, risk findings and history;
  exported and copied rows include the new fields.
- **Streaming port scans.** Results appear as each port answers through a
  sliding concurrency window, so one hung port no longer blocks the rest.
- **In-app installs.** iperf3 and blueutil install from a single button via
  Homebrew, with live output and a copyable fallback command.
- **Uptime defaults.** A fresh Uptime Monitor starts with Cloudflare DNS,
  Google and GitHub HTTP checks every five minutes.
- Site Survey gains a floor-project picker with the unsaved project, point
  undo/removal, wall/room/AP tools, onboarding cards and a coverage inspector.
- Survey PDF exports respect the selected network filter and wall/room
  attenuation.

### Changed
- GeoIP loads this Mac's public address as soon as the tool opens.
- Traceroute, DNS, DNS propagation, port scan, UDP scan and uptime tables keep
  a useful minimum height instead of collapsing on launch.
- Site Survey coverage interpolation no longer discards sparse samples.
- DNS propagation rows join multiple records on one line so long answers are
  no longer clipped.

### Fixed
- The new Toolkit screens, Device Shelf, risk findings, Site Survey and
  installer UI are fully localized in Russian, English, German, French and
  Simplified Chinese.
- Boolean metrics such as DNS consistency and traceroute reachability honor
  the active locale.

## 5.0.3 — 2026-11-12

### Fixed
- **Visual Traceroute now traces.** macOS `traceroute` sends UDP probes by
  default, and many routers and VPNs silently drop them, so every hop came
  back as `*` and the map had nothing to show. The runner now probes with
  ICMP first and retries with UDP when no hop answers; Traceroute and MTR use
  the same fallback.
- Visual Traceroute no longer waits for the whole trace before showing
  anything. Hops stream in as `traceroute` prints them, so the hop list,
  progress card and map fill in live.

### Added
- The Visual Traceroute map is always visible: the local egress point and the
  target are geolocated when the trace starts, and the route is drawn hop by
  hop with RTT-coloured segments, numbered hop pins, a highlight on the hop in
  flight and an RTT legend.

## 5.0.2 — 2026-11-12

### Fixed
- **Local Network gating.** LanFi now requests macOS Local Network access
  in-process before scanning; reading the ARP table through the `arp`
  subprocess never triggered the permission prompt, so the app stayed
  unauthorized. The scanner reports when the ARP table is unavailable and
  shows an actionable gate (Open Settings, Request access, Rescan) instead of
  a passive note, and the shelf no longer ingests identity-free fallback rows.

### Docs
- `docs/mcp.md` documents the Device Shelf tool in full: storage location,
  every argument, the row schema and a runnable example.

### Tooling
- Removed a stale local `post-commit` hook that pointed at a deleted
  `scripts/autopush.sh` outside the repository.

## 5.0.1 — 2026-11-12

### Added
- MCP `lanfi_devices`: read the Device Shelf with optional `online`,
  `favourite`, `risky`, `search` and `limit` filters, including risk findings
  and scores per device.

### Changed
- Removed the duplicate "Wi-Fi Networks" sidebar item — it opened the same
  screen as the Wi-Fi Analyzer. Old selections migrate automatically.
- The Device Shelf Risks filter and counter now only consider medium-and-above
  findings, so ordinary HTTP admin pages and UPnP no longer mark every device
  as risky.
- Alias edits are debounced before the shelf is written to disk.

### Fixed
- An empty sweep (denied Local Network access, interface down) no longer marks
  the whole shelf offline or counts against availability.
- Devices with no identity signal at all (no MAC, hostname, vendor, ports or
  gateway role) are no longer added to the shelf from a bare ICMP sweep.
- The Devices tab no longer floats in the middle of an empty window.

## 5.0.0 — 2026-11-12

### Added
- **Device Shelf** in the LAN Scanner: a persistent device inventory that
  survives rescans. Every device keeps a name (alias), a guessed type, vendor,
  MAC, open ports, availability over all scans, latency trend, security
  findings with a risk score, an event history (joined / back online / left /
  ports changed) and CSV/JSON export.
- Refresh countdown in the Wi-Fi analyzer toolbar next to Refresh/Pause, so the
  next automatic scan is always visible.
- MCP `lanfi_spectrum` for hardware spectrum CSV traces (span, noise floor,
  peak, per-band maxima, share of the trace above −70/−60/−50 dBm).
- `--bottom-tab` debug flag for toolkit snapshots.

### Changed
- The Network Toolkit is the app's main window; the Wi-Fi analyzer lives inside
  it, the separate toolkit window is gone.
- Wi-Fi filters moved from the collapsible sidebar into a taller top filter bar
  with wider band chips and a prominent Filters button; active filters tint
  their control instead of relying on a status line.
- The bottom status strip in the network list was removed; the network count
  stays in the toolbar and filter bar.
- Toolkit sidebar width, inspector width and bottom panel height persist across
  launches.
- Hardware Spectrum, Analyze Capture and Remote Sensors open as full-size
  sheets from the analyzer's Wi-Fi Tools menu; Capture/Spectrum/History stay in
  the bottom tabs without duplicate toolbar entries.
- Live capture scrolls its form and keeps Start Capture pinned in the short
  bottom panel.
- MCP grew to 25 tools and its protocol core is unit tested.

### Fixed
- iperf3 deadlock while reading pipes.
- DNS mail lookup stuck in a running state after cancellation.
- Cancelled port scans overwriting newer results.
- Stale LAN Scanner service banners after a rescan.
- Network Monitor route cache never refreshing.

## 4.13.0 — 2026-11-11

### Added
- Network Toolkit sidebar search and a persisted Recent list.
- DNS Propagation across six public resolvers, with expected-value matching.
- Whois reports over RDAP for domains and IPs, without shelling out to `whois`.
- GeoIP lookup with hostname resolution, country flag, ASN/ISP and Maps link.
- Visual Traceroute with a MapKit route, public-hop GeoIP and per-hop RTT.
- Ping continuous mode and TCP port presets.
- Traceroute probe count, per-probe timeout and optional name resolution.
- MTR latency-by-hop chart, standard deviation and continuous mode.
- DNS Lookup tabs: Records, Mail (MX/SPF/DMARC/DKIM) and a copyable posture report.
- Speed Test Result/History tabs; Internet Check Quick/Full with a speed pass.
- Subnet Calculator accepts IP + netmask and has a “This Mac” network shortcut.
- Path Check probes up to 32 ports per run, with presets and per-port results.
- Port Scan detects HTTP/SSH/FTP/SMTP service versions and optional UDP probes.
- iperf3 stores up to 12 servers and a persisted 50-entry measurement history.
- Network Monitor has Overview/Routes tabs; Routes parses the IPv4 `netstat` table.
- LAN Scanner detects service versions for a selected device.
- Uptime Monitor targets for HTTP, TCP, TLS, DNS and mail posture (MX/SPF/DMARC).
- New screens localized across all five shipped languages.

### Changed
- The Network Toolkit button sits next to the main search field with a prominent
  bordered style; duplicate toolbar entries were removed.
- Site Survey / heatmap is a separate toolkit sidebar item again, embedded in
  the detail pane. Its toolbar is split into two compact rows, with icon-only
  secondary actions and tooltips.
- Removed the duplicate Site Survey sheet from the Wi-Fi Analyzer workspace.
- Consistent tool header (icon, name, section), transparent-proxy warning in
  Port Scan, and iperf3 control/error layout fixes.

### Fixed
- Survey controls no longer clip in the toolkit; Russian labels fit the new
  two-row toolbar.
- Localized Internet Check titles/summaries, LAN Scanner status, Wi-Fi redirect
  copy and diagnostic warnings.

## 4.12.1 — 2026-11-11

### Changed
- The Tools menu and its dropdown are gone. The main toolbar opens the Network
  Toolkit directly, and the toolkit command lives under Layout (⇧⌘T).
- Site Survey, Hardware Spectrum, Live Capture, offline capture analysis,
  Remote Sensors and the specialised system tools now live inside the toolkit
  as sheets or embedded screens; their separate Tool/Survey/Spectrum windows
  and the old toolbar submenu were removed.
- Advanced Tools joins Network Tools and embeds the previous ToolConsole
  instead of opening a Tool window. LinkLiar and Wireshark are links there.
- The duplicate live-capture toolbar button was removed; Capture is a single
  control.

### Fixed
- Site Survey sheets now request enough space and the heatmap takes the
  remaining height instead of being clipped by the window.

## 4.12.0 — 2026-11-11

### Added
- Network Toolkit window (Tools → Network Toolkit…, ⇧⌘T): grouped sidebar
  with Internet Check, Ping, Traceroute, Speed Test, DNS Lookup, SSL
  Certificate, Port Scan, Path Check, Subnet Calculator and Network Monitor.
- Native probe layer behind the toolkit: unprivileged ICMP and TCP ping,
  a UDP DNS client with A/AAAA/MX/TXT/NS/SOA/CNAME/SRV/CAA records, a
  bounded-concurrency TCP port scanner, TLS chain inspection, and a
  traceroute runner/parser. 49 new headless tests.
- Internet Check now returns a plain-language verdict — Wi-Fi, router,
  provider, DNS or web — with a path diagram and supporting checks.
- Speed Test shows a bufferbloat grade derived from Apple's responsiveness.
- Deep link `lanfi://toolkit/<tool>` for opening a named tool.
- MTR: repeated traceroute with per-hop loss, last/avg/best/worst and jitter.
- Speed Test: persisted 50-run history and an hourly, 6-hour or daily schedule.
- Uptime Monitor: HTTP/HTTPS and TCP targets, seven-day history, outage
  counts, UserNotifications on down/recovery and status in the existing menu
  bar. No second menu-bar item.
- LAN Scanner: ARP when macOS exposes it, plus an ICMP/TCP fallback, Bonjour
  host names, OUI vendors, open ports and Network Guard for new devices.
- iperf3 client: upload/download/bidirectional runs against your own server,
  parsed from iperf3 JSON with an install hint when the binary is missing.
- Sidebar: Wi-Fi is the top section and Wi-Fi Analyzer is selected by default;
  its workspace hosts Site Survey, Hardware Spectrum, Live Capture, offline
  capture analysis and Remote Sensors. Monitoring follows, then Diagnostics,
  DNS & Domains and Network Tools.
- Network Monitor is now the toolkit's embedded Interfaces view; Interfaces and
  Diagnostics were removed from the main window's bottom tabs. The Tools menu
  keeps a single Network Toolkit entry, and Diagnostics shortcuts open the
  toolkit.
- Toolkit static strings are localised in English, Russian, German, French and
  Simplified Chinese (697 keys per language, no duplicates).
- 20 new headless tests (244 total).

## 4.11.1 — 2026-10-31

### Fixed
- Removed the duplicate band quick-filter chips from the toolbar: the
  sidebar filter panel already carries the same 2.4/5/6/Wi-Fi 7/Other
  chips, so the toolbar copies were redundant (and the toolbar "Band
  chips" preference is gone with them).

## 4.11.0 — 2026-10-31

### Added
- Hardware spectrum window (Tools → Hardware Spectrum, ⇧⌘Y): live RF
  sweeps from an RF Explorer analyzer over its USB-serial port (official
  UART protocol: `#C2-F:` config, `$S/$s/$z` sweep packets), with
  max-hold, peak marker, Wi-Fi channel guides and CSV export.
- Wi-Spy device detection over USB (I/O Registry): the app reports the
  connected MetaGeek model; Chanalyzer CSV traces import into the
  hardware spectrum view.
- Spectrum CSV import: Chanalyzer exports and any frequency/dBm table.
- Toolbar: band quick-filter chips (2.4/5/6 GHz — the toolbar toggle in
  settings was wired but never rendered), pause/resume auto-scan button,
  and a Hardware Spectrum shortcut.
- Survey heatmap: continuous red→green palette replaces the four hard
  bins, and the interpolated grid is memoised — hover and layout redraws
  no longer re-run IDW interpolation over every cell.

## 4.10.0 — 2026-10-30

### Added
- Wi-Fi 7 preamble puncturing: the EHT Operation element now decodes the
  Disabled Subchannel Bitmap and reports which 20 MHz subchannels are
  punctured (new "Puncturing" column, inspector detail and analyzer fact).
- `lanfi-cli pcap --json` now includes `mloGroups` with per-link BSSID,
  channel and RSSI, and prints MLO group lines in text mode.
- Opt-in automatic OUI vendor database update: when enabled in Vendor
  settings, the app refreshes the vendor list weekly in the background
  (default off; the app's first and only network request).
- German, French and Simplified Chinese localizations (application is now
  available in 5 languages, matching WiFi Explorer Pro).
- Accessibility labels on the remaining icon-only buttons (delete filter,
  remove condition, delete sensor, delete coloring rule, delete expression
  column, delete controller account) and the decorative Wi-Fi indicator is
  hidden from VoiceOver.

## 4.9.0 — 2026-10-30

### Added
- Complete MLO link sets in offline capture analysis: beacons sharing one AP
  MLD are merged into MLO groups with per-link BSSID, channel, RSSI and a
  captured/not-captured flag (new MLO… sheet and `mloGroups` in JSON export).

### Fixed
- Removed 33 duplicate keys from the Russian localization; duplicate `.strings`
  keys have undefined lookup behavior and could show the wrong translation.
- Disambiguated colliding Russian translations: open-network count
  ("Open networks"), interface count ("Interfaces Up") and the remote-sensor
  scan button ("Scan Remote") now use their own keys.
- Protocol coverage/distribution cards and diagnostics snapshot/throughput
  labels now render through `LocalizedStringKey`, so "PHY generations",
  "Security modes", "Bands", "Link rate", "Download", "Upload", "Latency" and
  "Responsiveness" are actually localized (they were always shown in English).
- Per-STA Profile BSSID in the Multi-Link element was read one byte early
  (the STA Info Length octet was mistaken for the first MAC byte).

## 4.8.0 — 2026-10-30

### Spectrum
- Clip network polygons to the plot so channel 1 shapes no longer spill into
  the left ruler.
- Added a live hover readout (band/channel/dBm), selected-network summary,
  band counts and noise floor.
- Added a Capture shortcut in the Spectrum header.

### Context menu
- Rich network menu header now includes model/AP name, SSID, band, channel,
  width, security, signal, noise, SNR and quality.

### Version
- 4.8.0 (build 53).


## 4.7.0 — 2026-10-29

### UI
- Primary toolbar buttons for Capture, Diagnostics, Survey and Tools; a
  compact Actions menu replaces them when the window is narrow.
- Rich right-click menu on networks: header with model/band/channel, quality,
  signal/noise/SNR, Show Details, Spectrum, History, Channel recommendation,
  copy actions.
- Capture moved to a main-window tab with channel selection, profiles,
  triggers, BPF, auto-open in Wireshark and Wireshark action.
- Removed paid Airtool link; clean-room capture workflow lives in LanFi.
- Human-readable tool names and grouped tool menu.

### Version
- 4.7.0 (build 52).


## 4.6.2 — 2026-10-29

### Fixed
- Visible **Tools** menu in the main toolbar with grouped network tools,
  Site Survey, capture, remote sensors and external tools.
- Tool windows open from the toolbar and can be full-screened.

### Version
- 4.6.2 (build 51).


## 4.6.1 — 2026-10-29

### Fixed
- Controller-supported channel plans are cached by AP MAC and consumed by the
  channel advisor before Country IE/regulatory fallback.
- Channel advisor source precedence: controller → Country IE → wireless-regdb →
  generation.

### Version
- 4.6.1 (build 50).


## 4.6.0 — 2026-10-29

### Channel capability providers
- Country IE (IE 7) parsing adds AP-advertised channel constraints.
- Bundled wireless-regdb country regulatory database (ISC) as fallback.
- Channel advisor applies country IE, regulatory, generation and DFS filters.
- UniFi controller inventory exposes supported channel lists when the API
  returns them.

### Tool platform
- Reusable ToolConsole windows with availability detection, argument editing,
  copy/save, timeout and full-screen toggling.
- Toolbar Tools menu for wdutil, networkQuality, ping, traceroute, mtr, dig,
  dscacheutil, arp, nmap, blueutil, airport, captive portal, iperf3,
  hostapd_cli, SSH iw phy and custom commands.

### Version
- 4.6.0 (build 49).


## 4.5.0 — 2026-10-29

### Spectrum
- Corrected dBm-to-Y mapping (higher dBm is higher on screen) and added a
  full -100…-10 dBm ruler.
- Added a top margin so peaks and labels stay inside the plot.
- Full-screen Spectrum/History opens in a dedicated window.

### Channel advisor
- Connected/selected network now gets a same-band channel recommendation.
- Recommends a less loaded channel only when it improves by >=10 points;
  otherwise Keep current channel.
- Filters candidates by Wi-Fi generation (no 6 GHz for 11n), avoids DFS when
  the current channel is non-DFS, and surfaces the advertised router model.
- Channel advice shows current score, target channel/width, DFS warning and
  reason.

### Version
- 4.5.0 (build 48).


## 4.4.1 — 2026-10-29

### Fixed
- Spectrum capabilities are refreshed on each scan, so switching CoreWLAN
  interfaces (including external adapters) updates the available channel lanes.

### Version
- 4.4.1 (build 47).


## 4.4.0 — 2026-10-29

### Spectrum
- Spectrum lanes are generated from CoreWLAN `supportedWLANChannels()`
  instead of hard-coded 2.4/5/6 ranges, including an Other lane for future bands.
- Available channels are sampled per adapter capability; lanes adapt to the
  active Wi-Fi interface.
- Band filters include an explicit Other filter and are persisted in filter
  profiles.

### Version
- 4.4.0 (build 46).


## 4.3.0 — 2026-10-29

### Fixes
- Spectrum vertical scale no longer clips labels at the top; both charts zoom
  in and out (0.5×–4×/8×).
- Band filters moved from the toolbar into the left filter sidebar; they are
  shared by table, Spectrum and History.
- Spectrum/History full-screen uses dedicated windows and no longer nests
  sheets; the window opens full-screen and can be toggled.
- Network table security is parsed from RSN/WPA information elements instead
  of CoreWLAN support masks (WPA2/WPA3/OWE/transition/PMF).
- Removed the redundant Raw Data “Network fields” tab.
- Vendor icons, toolbar status/survey action and PCAP search/JSON/Wireshark
  controls completed.

### Version
- 4.3.0 (build 45).


## 4.2.0 — 2026-10-29

### UI and workflows
- Network context menu: copy cell, copy visible row, copy BSSID; targets fixed.
- Spectrum shows all bands with 2.4/5/6 GHz labels and channel ticks; band
  picker removed. Top-band filter is shared by Spectrum and History.
- Spectrum/History: zoom, fullscreen, PNG/SVG/CSV export.
- Vendor icons in the vendor column.
- Raw Data: Network fields / Information elements switch; more fields.
- Smooth expand/collapse animation in Raw Data.
- Inactive interfaces visible by default without the grey disclosure panel.
- Diagnostics buttons enlarged; speed test moved above checks and enlarged.
- All text selectable where SwiftUI supports it.
- External tools menu: LinkLiar, Wireshark, Airtool, iPerf3, networkQuality.
- English source localization template and localization docs.

### Version
- 4.2.0 (build 44).


## 4.1.0 — 2026-10-27

### License
- Relicensed new source and releases from MIT to **FSL-1.1-ALv2**
  (Functional Source License, Apache-2.0 future license).
- Added trademark policy for the LanFi name/logo.
- Existing MIT releases remain MIT; the new terms apply going forward.

### Version
- 4.1.0 (build 43).


## 4.0.0 — 2026-10-27

### Changed — full LanFi identity
- Bundle identifier changed from `ru.zheltukheen.WiFA` to
  `ru.zheltukheen.LanFi` (app, tests, CLI).
- All `Wifa.*` preference keys, Application Support paths, queue labels,
  URLs, docs, scripts and cask references renamed to `LanFi`/`lanfi`.
- GitHub repository renamed to `zheltukheen/lanfi`; release/appcast URLs updated.
- Removed obsolete pre-rename migration blocks.
- Build 42, ad-hoc re-signed.


## 3.2.1 — 2026-10-27

### Changed
- Spectrum and History show all networks when 0 or 1 network is selected,
  and only the selected set when 2+ networks are selected.

### Version
- 3.2.1 (build 41).


## 3.2.0 — 2026-10-27

### Changed
- Sidebar filters now follow visible table columns directly. Hiding a column
  removes its filter; showing a column adds it. Only SSID is excluded.
- Shared comparison table used by both the side inspector and bottom panels.
- Custom OUI override fields have labels and placeholders.
- Toolbar is configurable: band chips, search, export and capture can be hidden.
- General settings include theme, row density and scan-on-launch.
- OUI/settings/top bar cleanup.

### Fixed
- Stale quick filters no longer survive hiding their column.
- Duplicate comparison implementations removed.

### Version
- 3.2.0 (build 40).


## 3.1.3 — 2026-10-27

### Added
- UniFi controller RF telemetry in the AP inventory: channel, clients,
  TX power and channel utilization when exposed by the controller.

### Changed
- Version 3.1.3 (build 39).


## 3.1.2 — 2026-10-27

### Added
- Scheduled scan reports can now be exported as PDF as well as CSV.
- PDF scan report with visible columns, title, timestamp and paginated rows.

### Changed
- Version 3.1.2 (build 38).


## 3.1.1 — 2026-10-27

### Added
- Import a scan from an HTTP(S) URL (LanFi JSON or CSV).
- High-contrast styling extended to About/Help and sidebar cards.

### Changed
- Version 3.1.1 (build 37).


## 3.1.0 — 2026-10-27

### Added
- SNMP controller inventory via /usr/bin/snmpwalk (host + OID + community,
  community stored in Keychain).
- Floor-to-floor 3D coverage prediction: floor levels, vertical distance,
  12 dB/floor attenuation, predictive overlay in the 3D multi-floor view.
- New floors get monotonic floor levels automatically.

### Changed
- Version 3.1.0 (build 36).


## 3.0.0 — 2026-10-27

### Added
- Sidebar filters now derive from table columns (single source of truth);
  non-filterable SSID is excluded and new categorical columns are included.
- Multi-network comparison in the bottom Profile and Raw Data panels.
- Per-graph visibility toggles for channel recommendations, security audit
  and channel occupancy.
- Interactive multi-floor 3D stack view.
- BSSID-appearance triggered capture.
- Two-point plan-scale calibration.
- Wi-Fi 7/MLO inspector with AP MLD, link IDs, per-link BSSIDs and 320 MHz.
- Scheduled CSV reports while LanFi is running.
- On-demand live client discovery via a short monitor capture.
- UniFi and Meraki controller inventory with Keychain-stored API tokens.

### Changed
- Version 3.0.0 (build 35).


## 2.9.3 — 2026-10-26

### Added
- Per-link MLO BSSID extraction from Multi-Link per-STA profiles; link BSSIDs
  are shown in the IE details.
- Additional accessibility labels on survey and capture controls.

### Changed
- Version 2.9.3 (build 34).


## 2.9.2 — 2026-10-26

### Added
- Remote capture over SSH: run tcpdump on a saved remote sensor, copy the pcap
  back, with interface/duration/monitor/BPF options and passwordless-sudo error
  reporting.
- Remote capture command validation and tests.

### Changed
- Version 2.9.2 (build 33).


## 2.9.1 — 2026-10-26

### Added
- High contrast mode (Settings → General), stronger row tint and accessibility
  labels on table cells.
- Capture start delay as a simple trigger primitive (0/5/10/30 seconds).

### Changed
- Version 2.9.1 (build 32).


## 2.9.0 — 2026-10-26

### Added
- Offline IE detail panel with copy; client MAC discovery from pcap/pcapng.
- Predictive survey AP placement and coverage model; predictive APs in PDF.
- USB hardware inventory (spectrum analyzers, WLAN Pi, SDR, 802.15.4) in Settings.
- 6 GHz/DFS/regulatory and Zigbee/Thread availability inspectors.
- Custom expression columns, generic scan importer, capture profiles with BPF,
  IE copy and hide-empty-graphs setting.
- Expanded Russian localization for the new workflows.

### Changed
- Version 2.9.0 (build 31).


## 2.8.1 — 2026-10-26

### Added
- Offline PCAP client discovery: unique client MACs, associated BSSID and frame
  counts from monitor captures, with a dedicated Clients sheet.
- Zigbee/Thread and 6 GHz regulatory/DFS inspector sections.

### Changed
- Version 2.8.1 (build 30).


## 2.8.0 — 2026-10-26

### Added
- Predictive survey: place virtual APs on the floor plan and render a
  log-distance/wall-aware coverage heatmap; APs and predictions appear in PDF.
- 6 GHz/DFS/regulatory inspector and an explicit Zigbee/Thread availability
  section.
- Custom expression columns, generic JSON/CSV scan import, BPF capture profiles,
  PCAP IE/client counts, IE copy and hide-empty-graphs settings.

### Changed
- Version 2.8.0 (build 29).


## 2.7.0 — 2026-10-26

### Added
- Survey walking mode with throttled automatic sampling.
- Room obstacle polygons with attenuation; scale, client/title/notes metadata.
- Branded PDF reports and an all-floors portfolio PDF.
- Generic scan importer for LanFi JSON and CSV.
- Capture profiles and BPF filter expressions.
- PCAP IE decoding and BSS-Load client counts in offline analysis.
- Custom expression columns with tokens and Settings editor.
- Copy all/selected information elements.
- Hide empty graphs setting.

### Changed
- Version 2.7.0 (build 28).


## 2.6.0 — 2026-10-26

### Added
- Custom filter builder: field/operator/value rules, AND/OR combinators,
  automatic presets (open, weak, 6 GHz, Wi-Fi 7, WPA3, hidden) and persistence.
- Coloring rules with automatic row tint and manual per-network color.
- Unified workspace profiles: filters, bands, columns, coloring rules, custom
  filters and active rule in one profile.
- Per-network Issues inspector, signal/noise/SNR history chart and channel
  utilization history.
- iBeacon proximity inspector and BSS-Load client count inspector.
- Detailed multi-select comparison (band, width, SNR, security, quality).
- Settings Colors tab; About/Help windows.

### Changed
- Sidebar filters support multiple values per category and larger rows.
- Sidebar sort popover, Wi-Fi 7 chip, rule picker and custom filter editor.
- Version 2.6.0 (build 27).


## 2.5.4 — 2026-10-26

### Added
- Multi-select values inside every sidebar filter category (network, mode,
  channel, width, security, access point, vendor). Values within a category
  are ORed; categories are ANDed. All clears one category.
- Larger filter rows and a clearer selected state.

### Changed
- About/Help windows included in the shipped build.
- Layout menu avoids collision with the localized system View menu.


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
  `brew tap zheltukheen/lanfi https://github.com/zheltukheen/lanfi`.


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
- **Renamed the app from LanFi to LanFi.** The product, executable, Xcode project, scheme, cask, DMG/ZIP names, menus, About panel, appcast and documentation now use the LanFi brand. The internal bundle identifier remains `ru.zheltukheen.LanFi` so existing preferences, Location permission and Sparkle updates continue to work.
- **New bold app icon** (radar/Wi-Fi mark with an L monogram) across Dock, Finder, About panel and release bundles.
- **Bottom panel is taller** (460 pt by default, capped to 60% of the window) and tabs are grouped into Overview, RF, Network and Troubleshoot categories.
- **Insights scope is explicit**: a banner states that insights cover all visible networks and shows the currently connected network.
- **Protocols is explicitly scoped to the selected network**, with a six-block order (radio, security, spectrum, roaming, format, vendor), numbered cards and a fixed card height so blocks no longer jump in size.
- Localized bottom-panel categories and new scope labels; migrated annotations, sessions and surveys from the old `LanFi` Application Support directory.

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
- The Xcode project now enables hardened runtime and uses a stable bundle identifier (`ru.zheltukheen.LanFi`).

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
