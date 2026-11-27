# Changelog

## Unreleased

### Changed
- **Location Services is asked once, at launch, for the whole app.** The request
  and the status check moved out of the Wi-Fi analyzer into `LocationAccessCenter`,
  so every screen sees the same answer and picks up a change made in System
  Settings. A wide prompt names the features that depend on the permission and
  offers Allow / Open Settings / Check Again / Continue without; a one-line
  banner in the app shell reopens it from any tool. The analyzer no longer
  replaces its table with a permission empty state — without access it keeps
  showing signal and channels and the banner explains what stays hidden.

### Added
- **Switch port lookup (G15).** The LAN scanner can ask a switch where a device
  is plugged in: it walks the BRIDGE-MIB and Q-BRIDGE forwarding tables and the
  LLDP neighbours read-only, then shows the port, the VLAN (and its name) and
  the port's far end for the selected MAC. The sheet is opened from the device
  inspector, defaults to the scan's gateway, keeps the community in memory for
  that one read and says so. Devices behind another switch, on Wi-Fi, or absent
  from the table are reported as such instead of guessed.
- **An authorized device inventory.** Network Guard now remembers every device
  with its first and last sighting and a trust flag the user sets per device or
  for the whole list. The scanner shows how many devices are not trusted yet
  and how many known devices this scan did not return. Files written by the old
  key-only guard are adopted as trusted, so upgrading does not flag the whole
  network as unverified.
- **Reliability score and problem history (G10).** The Wi-Fi Monitor no longer
  only plots the recorded window; it judges it: a score out of 100 with a
  grade, the share of samples at a weak signal, and a ranked problem list
  (disconnects, failed roams, deauth bursts, security, gateway, DNS and VPN
  changes, channel changes) with counts and time ranges. Fewer than ten samples
  or five minutes of history reports “not enough data” instead of scoring
  noise. The combined HTML and PDF report gained the same Reliability section.
- **Inferred device types.** A scanned device's kind is now chosen from a shared
  classifier (advertised role, then Bonjour/UPnP services, then open ports, then
  the MAC vendor or hostname), and the inspector labels the row “Kind ·
  inferred” unless the device described itself.

## 5.7.0 — 2026-11-26

### Added
- **A “Support LanFi” button at the bottom of the sidebar.** It opens a sheet
  with one button per support destination (Boosty and DonationAlerts today),
  read from the same `.github/FUNDING.yml` that GitHub renders for the
  repository's Sponsor button.
  The file is copied into the app at build time, so the list changes with a
  rebuild and nothing is downloaded at run time.
- **Client card and a signal locator.** The Captured clients table now opens a
  detail sheet for one client: vendor, SSID/BSSID, first and last frame, frames,
  retries, airtime and probes, plus the PHY generations, MIMO order, supported
  rates, 802.11r and PMF capability decoded from its association request (its
  AP's beacon is used, and labelled as such, when no association frame is in the
  capture). The same sheet has a locator: it samples the BSSID's RSSI as fast as
  CoreWLAN returns scans, shows a smoothed large readout with a trend line and a
  sparkline, reports “signal lost” after three seconds of silence, and can ping
  when the signal gets stronger. It is labelled signal guidance, not direction
  finding, and states that it follows the access point because macOS exposes
  per-client RSSI only during a privileged monitor capture.
- **Per-BSSID airtime and a legacy 802.11b flag.** A capture now attributes the
  airtime each access point reserved (Duration/ID of its transmitted frames) and
  ranks the BSSIDs, so “the channel is busy” becomes “the neighbour's AP took
  68% of it”. Client Analytics gains a Channel airtime table and an insight for
  the busiest BSSID. A new **Legacy 802.11b** column and inspector row flag an AP
  that advertises only 1/2/5.5/11 Mbit/s basic rates, and directed data frames
  sent at those rates are counted from the radiotap rate.
- **Decoded-field catalogue and field-backed columns.** Data → “Decoded
  Fields…” lists every value LanFi decoded but does not tabulate — frequency,
  DFS/PSC, puncturing, beacon timing, basic rates, WPS model, PMF, 6 GHz power
  mode, MLO links and each information element including vendor IEs. Any field
  can be promoted to a real column by its stable key (`radio.frequency`,
  `mlo.apmld`, `ie.element.221.0`). “Export CSV (All Decoded Fields)…” writes
  one column per field key across the whole scan, with absent values left
  empty rather than guessed.
- **Survey pass/fail requirement.** Surveys can be judged against the user's own
  thresholds (minimum RSSI, optional minimum download and maximum latency). The
  profile is off until chosen, the plan marks failing points with a red ring,
  the inspector shows pass percentage, failing points and the worst area, and
  the PDF and combined HTML report carry the requirement and its verdict. Noise
  and SNR are not recorded per point, so they are not judged or invented.
- **Foreign scan CSV files import with their own column names.** The importer
  now recognises AirPort Utility, Aruba Utilities, Analiti and Mobile Eye style
  headers, units in cells (`-52 dBm`, `80 MHz`), frequency-only exports
  (channel and band derived), and reports the columns it could not map instead
  of dropping them silently.
- **Scan snapshots and a diff between two of them.** Data → “Save Scan
  Snapshot…” stores the visible scan under a name, and “Compare Snapshots…”
  opens a window where A is the older scan and B the newer one: added, removed
  and changed BSSIDs, with channel, width, security, generation and a signal
  shift of 10 dBm or more. The diff exports to CSV; snapshots live in
  `~/Library/Application Support/LanFi/scan-snapshots.json` and are never
  uploaded.
- **Environment baseline with a “new access point” alert.** The first scan of a
  place seeds a local baseline of BSSIDs; later scans report BSSIDs outside it
  once — in the Monitor event log, as an optional notification, and as a card in
  Security Watch with Accept / Reset actions. Pending BSSIDs survive a
  relaunch; moving to a different site is one Reset away. New alerts are on by
  default and share the existing per-kind cooldown.
- **Capture limits: size cap, rotated parts and data-frame slicing.** A live
  capture can now rotate the file at 50/100/250/500 MB (tcpdump `-C`); the
  numbered parts are merged back into the single file the rest of the app reads,
  so analysis, MCP and profiles keep working unchanged. “Data frames” truncates
  data-frame payloads to 128/256/512 bytes after the capture while leaving every
  management and control frame whole, so IE decoding is unaffected. Captures can
  also run up to 10 minutes now, not 2.
- **Live Wireshark streaming and a Stop button.** With Wireshark installed, the
  capture is tailed into a `wireshark -k -i -` session while tcpdump is still
  writing, so frames appear live without running Wireshark as root; the file is
  still saved. Stop writes a marker next to the capture that the privileged
  shell checks once a second, which ends the run without a second password
  prompt.
- **Multi-channel capture control.** A channel list longer than one is now tuned
  by LanFi during the capture (100/150/250/500 ms dwell) instead of being left
  to macOS, with the band kept alongside the channel number so a 6 GHz PSC and a
  2.4 GHz channel with the same number are not confused. “6 GHz: preferred
  scanning channels only” filters the band’s channel list to PSC.
- **DNS-over-QUIC in the DNS console.** The Compare card now queries AdGuard and
  Google over DoQ (RFC 9250) next to the UDP, DoH and DoT rows, with
  `quic://host:port` for a custom resolver. A blocked QUIC path is shown as a
  failed row, not dropped.
- **Per-client airtime and retries in Client Analytics.** The capture pass sums
  each client's Duration/ID field and counts retransmissions, so the clients
  table shows Retries and Airtime per client and the insights call out a high
  retry rate and a single client that dominates the channel.

### Changed
- **The OUI vendor index is cached as a binary file.** The packed lookup table
  is written to `oui-index.bin` and reused while its fingerprint matches the
  text database, so a cold launch no longer reparses the 1.7 MB list before the
  first scan can name a vendor.

## 5.6.34 — 2026-11-22

### Fixed
- **The supervised-process startup test no longer races the scheduler.**
  `testChildThatExitsDuringStartupFailsTheStart` now yields in the readiness
  probe before answering, so the child's exit is observable even on a loaded
  CI runner. The flaky failure stopped the v5.6.33 release before any artifact
  was published.

### Changed
- **First published release since 5.6.16.** This build ships every change from
  5.6.17 through 5.6.33, and the release notes collect all of those sections
  below this heading.

## 5.6.33 — 2026-11-22

### Changed
- **Tagged, but never published.** The tag's release run failed on the flaky
  supervised-process test above, so nothing was released. Its changes ship in
  5.6.34 together with every version from 5.6.17 to 5.6.32.

## 5.6.32 — 2026-11-22

### Changed
- **One chip and one list row.** Band filters, scan-mode chips and the filter
  popover button now share `AppChip`; Uptime targets and connection-rule targets
  use `AppListRow`. Selection, tint, height and stroke no longer drift between
  the analyzer bar and the toolkit.
- **Surface tokens instead of repeated colours.** Warning banners, connected-
  network pills, scanner blocks and chart bars use `DesignToken.Surface`
  (`warningFill`, `dangerFill`, `tintFill`, `selectionFill`, `border`) instead of
  per-screen opacity literals.

## 5.6.31 — 2026-11-22

### Added
- **Scheduled combined report.** Settings → Automation can now write the
  combined handover report as HTML on the existing timer, using the latest
  survey, current scan, speed history and monitor events. Scan CSV/PDF
  snapshots stay available.
- **WFA Capabilities decoding.** Wi-Fi Alliance vendor element 0x23 now names
  QoS Management DSCP Policy, Unsolicited DSCP Policy and Non-EHT SCS Traffic
  Description, with the raw bitmap and extra octets shown.

## 5.6.30 — 2026-11-22

### Added
- **No-coverage cutouts in surveys.** A new Cutout tool draws polygons for the
  outside of the building, lift shafts and sealed voids. Measured and predicted
  heatmaps, the 3D view and the PDF report leave cut-out cells empty instead of
  painting signal there. Old survey files decode with no cutouts.

## 5.6.29 — 2026-11-22

### Added
- **Multi-floor measured/predicted diff.** The 3D survey view now shows a chip
  per floor with its measured average, its predicted average from an 8×8 grid
  and the delta, coloured when the model is off by more than 6 dB. It follows
  the floor-loss slider, so a whole-building comparison stays consistent with
  the coverage overlay above it.

## 5.6.28 — 2026-11-22

### Added
- **Calibration against walk samples.** When a survey has access points and at
  least three measured points, the app compares measured RSSI with the predicted
  value, applies the median offset to the predictive heatmap, 3D view and PDF
  report, and shows the offset, point count and residual in the Coverage card.
  A toggle turns it off; without enough points the model stays untouched.

## 5.6.27 — 2026-11-22

### Added
- **Antenna patterns in the predictive survey.** New access points can be omni,
  90° directional or 60° panel with an eight-way heading. The predictor applies
  a smooth off-axis loss (up to 15/20 dB behind), and “Apply antenna to all APs”
  updates an existing layout. Survey files without antenna fields decode as
  omni.

## 5.6.26 — 2026-11-22

### Added
- **Throughput and latency per survey point.** The Points card in Site Survey
  gains a Measure action: one networkQuality pass is attached to the newest
  point and saved with the project, so a walk records not just RSSI but the
  throughput actually available at that spot. Points without a measurement keep
  the old file format.

## 5.6.25 — 2026-11-22

### Added
- **Measured roam impact.** Roaming Test can now start a gateway loss probe:
  native ICMP once a second while walking. Every BSSID transition gains its
  packet loss over ±3 s and the reconnect gap between the last reply before the
  roam and the first reply after it, shown per roam and as average loss and
  worst reconnect in the summary card.

## 5.6.24 — 2026-11-22

### Added
- **Material-aware survey walls.** The structure menu now draws walls as
  drywall (3 dB), wood (4 dB), glass (6 dB), brick (10 dB), concrete (15 dB) or
  metal (25 dB) at 5 GHz, and the preset is stored with the wall. Older survey
  files and custom walls keep their 8 dB value.
- **Adjustable inter-floor loss.** The 3D multi-floor prediction takes a
  0–30 dB floor-loss value (default 12 dB) instead of the hard-coded term, so
  stacked floors can be modelled for the building rather than a generic slab.
- **Branded combined reports.** The survey's report title, client name and notes
  now head the combined report and add a Notes section in both HTML and PDF.

## 5.6.23 — 2026-11-22

### Added
- **PDF combined report.** Data → Export Combined Report as PDF… renders the
  same self-contained HTML report through WebKit and saves a paginated PDF, so
  handover no longer needs the browser's print dialog.
- **Scan CSV export from Shortcuts.** The new “Export the Wi-Fi scan” intent
  returns a dated CSV (SSID, BSSID, band, channel, width, signal, security,
  vendor) to Files or any Shortcut action.
- **RSNXE Override and RSN Selection decoding.** Vendor elements 0x2B and 0x2C
  from the Wi-Fi Alliance OUI now show field length, SAE H2E/SAE-PK, Protected
  TWT/WUR, Secure LTF/RTT, PBAC and the selected RSN variant, with truncation
  reported instead of a silently partial decode.

## 5.6.22 — 2026-11-22

### Added
- **Known networks are now an inventory, not a list.** Each saved SSID shows
  every visible BSSID with its best signal, band/channel, width, generation and
  live security. Counts cover saved, in range, not in range, weak security and
  visible-but-unsaved networks; filters and sorting apply to the list, CSV/JSON
  export follows the current view, and the detail pane lists all access points
  and warns about open, WEP or legacy WPA networks. Passwords are still never
  read.
- **802.11bn decoder versioning.** Protocol profiles stamp the tracked draft
  (`802.11bn D1.4`) and say that Wi-Fi 7 is decoded as 802.11be/EHT.

### Fixed
- **Tables reach the edges of their cards.** A table inside a padded card used
  to keep the card's side inset, leaving a narrow strip on both sides; tables
  now bleed to the card edge while cell text keeps its inset.

## 5.6.21 — 2026-11-22

### Added
- **Native diagnostics probe.** Ping no longer spawns `/sbin/ping`; LanFi
  builds and checks ICMP echo packets itself on an unprivileged datagram
  socket, so macOS cannot withdraw Local Network access from a child process.
- **Live capture counters.** The capture footer updates deauth, disassoc,
  EAPOL-Key, handshake, PMKID and burst counts once a second while tcpdump is
  still writing the pcap.
- **BLE beacon scanner.** Settings → Hardware passively decodes iBeacon and
  Eddystone UID/URL/TLM advertisements (no connection, no write) and shows
  RSSI, identifiers and telemetry. Zigbee is analysed as a 2.4 GHz coexistence
  map with quiet channels.
- **Spectrum hub.** Sweeps from RF Explorer, a Wi-Spy/Chanalyzer CSV, a remote
  WLAN Pi or a NetAlly export share one classifier for Wi-Fi, microwave,
  narrowband 2.4 GHz, cordless and wideband interferers; remote sources can be
  fetched over HTTP from the Source menu.
- **Router/NAS polling.** Read-only SNMP v2c GET of standard interface
  counters and SSDP discovery in Settings → Hardware. The community is asked
  per request and never stored.

### Changed
- Protocol profiles stamp the decoder draft (`802.11bn D1.4`) and state that
  Wi-Fi 7 is decoded as 802.11be/EHT.
- The Bluetooth usage description ships in Info.plist; new strings are in all
  five locales.

## 5.6.20 — 2026-11-22

### Added
- **Opt-in DNS switching.** The resolver benchmark now has a "System resolver"
section: it shows the chosen network service and its current servers, and
"Use…" on Cloudflare, Google or Quad9 opens a confirmation sheet with the
current and the pending servers before anything happens. Confirming runs
`networksetup -setdnsservers` plus the DNS cache flush through one macOS
administrator prompt. The previous setting is recorded only after success, so
"Revert to previous…" restores it, or DHCP when no manual servers were set.
Nothing switches automatically.
- **Contacted domains per app.** Process Traffic now attributes host names to
apps from a HAR opened on HTTP Traffic (IP → host only) and from cached reverse
DNS of connection endpoints, sampled every five minutes while Process Traffic
is on. The card shows the strongest host per app, can export CSV, and keeps
seven days. Only host names are stored; paths, query strings, cookies and
payload are never read, and LanFi's own connections are excluded.

### Changed
- The "App history" note now separates byte totals from host attribution
instead of claiming no domains are stored. New strings ship in all five
locales.

## 5.6.19 — 2026-11-22

### Added
- **MCP live actions.** `lanfi_scan_now`, `lanfi_start_capture` and
`lanfi_survey_sample` ask the running app to scan Wi-Fi, run one bounded
capture or tag the newest survey sample with the current location. Requests
travel through a local file mailbox (`MCPLiveActionStore`), are executed by
`MCPLiveActionService` on the app's view models and never open a port. Off by
default in Settings → MCP.
- **GPS Map.** A new Wi-Fi tool pins scanned networks on MapKit while an opt-in
trip records: open networks are red and secured ones green, the strongest
position per BSSID wins, and saved trips can be reopened or exported as
GeoJSON and CSV. Location is used only during a trip, stays local, and is never
attached to the live scan.

### Changed
- **Location copy and localisation.** The usage description now also covers GPS
trips, and the new GPS Map and live-action strings ship in all five locales.

## 5.6.18 — 2026-11-21

### Changed
- **One source list for the app, the CLI and the tests.** `project.yml` used to
repeat `Models`, `Services`, `Utils` and `CLI` in three targets; a shared
`targetTemplates.shared` entry now lists the common sources once. The Sparkle
updater moved to `App/`, so the standalone `lanfi-cli` binary still links no
Sparkle framework and the test bundle no longer depends on it.
- **Core probe and target models live in `LanFiCore`.** `ToolTarget`,
`MTRHop`/`MTRReport` and the route-monitor models (samples, window statistics,
route-change detection, thresholds, cadence) are a SwiftPM library with a
public API instead of being compiled into the app target. Probe screens import
the package; the Wi-Fi model layer stays in the app until it has a
Foundation-only seam.

### Accessibility
- **The last hand-rolled charts now match every other chart.** MTR and the
route-monitor heatmap drew a literal grid colour and 8 pt axis labels; both use
`ChartStyle` and `AppPalette`, so they follow the colour-blind palette and the
shared axis typography. The Help window hides its decorative symbols from
VoiceOver and labels its search field.
- **Design-pass status corrected.** The gap analysis now records D1, D4 and D8 as
closed, keeps D7 open for the hands-on VoiceOver run and contrast audit, and
records the measured fact that macOS ignores `dynamicTypeSize` instead of
promising an in-app text-size switch that cannot work.

### Engineering
- **CI covers the supported systems, the UI and performance.** The test job runs
on macOS 15 and 26; GitHub no longer offers 13 or 14 runner images, so the
13.0 deployment target is compiled and tested by the remaining images.
`scripts/ui_smoke.sh` lays out every available tool screen and both menu-bar
surfaces headlessly (`--ui-smoke`) and then runs the bundle check; screenshot
capture stays an opt-in local aid because it needs a GUI session.
`Tests/PerformanceBudgetTests.swift` enforces budgets
for a 300-network analysis, the JSON export and the 180-sample route window;
those budgets run in the normal suite.

## 5.6.17 — 2026-11-21

### Added
- **Continuous route monitor.** The new Route Monitor tool keeps one
traceroute target running through the existing MTR engine and keeps the last
180 rounds, so route flaps and evening congestion have a history instead of
being remembered. A scrolling heatmap shows latency and missed replies per hop
over time, with configurable latency and loss thresholds, edge-triggered
notifications for threshold crossings, and a route-change event that requires
the new path to appear twice before it is announced, so one timed-out hop does
not raise an alert. There is exactly one monitor app-wide: it slows to every
30 s while the screen is closed and every 60 s in the background, and the
menu-bar "Route" metric draws the destination latency next to the existing
throughput, signal, quality and latency metrics. Nothing starts until the user
presses Start.

## 5.6.16 — 2026-11-21

### Added
- **Block rules can be paused and edited.** Each rule has a switch that stops it
  from matching sockets without deleting it, and a pencil opens the same editor
  pre-filled, so changing a rule's scope or value no longer means deleting it and
  typing it again.
- **Rules export and import as JSON.** A rules file moves a rule set to another
  Mac or saves it before an experiment; importing merges by rule identity, so a
  second import updates instead of duplicating.

### Fixed
- **Table headers are localized.** Column titles were plain strings drawn
  verbatim, so LAN Scanner and the device shelf showed Device, Hostname, Vendor,
  Ports, RTT, Availability, Warranty and Last seen in English inside a Russian
  interface. Headers now resolve as localizable keys, and the column titles that
  had no translation yet were added in all five languages.
- **Stretched survey plans no longer skew the coverage prediction.** A hand-drawn
  plan fills the pane, so a pixel is not the same number of metres on X and on Y;
  the predictor used the plan width for both axes and reported the wrong
  distance. Predictive coverage now takes separate horizontal and vertical
  scales.

## 5.6.15 — 2026-11-21

### Changed
- **The site survey header is one row.** Floor, 3D, Plan, Map and the network
  picker sit on one compact strip; import, blank plan, save, PDF, report and
  clearing points moved into a file menu, and structure actions plus the heatmap
  detail into an overflow menu. The plan tool chips stay in the inspector, where
  they already were. The screen used to spend two stacked toolbars of small
  controls before the plan started.
- **A hand-drawn plan fills the workspace.** Blank plans are a metre grid, not a
  photograph, so they no longer sit centred as a square with empty bands on both
  sides; an imported floor plan still keeps its own aspect ratio so rooms are
  not stretched.

## 5.6.14 — 2026-11-21

### Fixed
- **The Connections screen no longer jumps upward when it opens.** Its summary,
  watcher card and a table of up to 640 pt made a `VStack` taller than the
  window, and SwiftUI clipped the overflow at the top, which pushed the tool
  header and the Sockets/Traffic/Rules tabs out of sight. The screen scrolls
  now, so the header and the tabs stay where they belong.
- Tab labels in the shared strip no longer wrap to a second line and clip; the
  rule sheet's scope caption is no longer squeezed out of its row.

## 5.6.13 — 2026-11-21

### Added
- **Rules from what is actually running.** The new-rule sheet offers three
  sources: running processes, installed applications and the manual form. Each
  list is searchable, shows the PID and bundle identifier, and fills the rule in
  from the selection, so a rule no longer starts with typing an executable name
  by hand. Helpers and XPC services that own sockets but no bundle are matched
  by executable name.
- **Suggestions on the Rules tab.** Apps with established sockets that no rule
  covers yet appear as one-click chips ("Safari — 3 connections"), sorted by
  activity, and the list refreshes after a rule is added.

### Changed
- Rule matching stays process-level (LanFi ships no packet filter and no root
  helper); the picker only changes how a rule is authored.
- `Models/RuleTargets.swift` keeps the catalog logic free of AppKit so it is
  unit tested; five tests cover merging, process scoping, ordering and the
  suggestion list.

## 5.6.12 — 2026-11-21

### Fixed
- **The analyzer's interval menu opens on click again.** The countdown pill used
  a `TimelineView` inside its own label, so the button got a fresh anchor twice
  a second and the popover it presented could be torn down immediately. The
  countdown is now a value updated by a timer, the label keeps one identity, and
  its chevron is large enough to read as "this opens a list".
- **Icon menus no longer sit tight against their border.** The gear and the
  share menu framed the bare glyph; both now use a shared icon label with the
  same chrome and side padding as the text menus beside them.

### Changed
- **Scan mode is a chip row.** Active/Passive/Directed are three chips in the
  table filters' style instead of a native-looking popup, so the current mode is
  visible at a glance. The toolbar gave up its duplicate "N networks" caption
  (the filter strip already shows visible/total) and a narrower search field to
  make room, and "Passive"/"Directed" are now translated in all five locales.

## 5.6.11 — 2026-11-21

### Fixed
- **One header strip everywhere.** DNS Lookup/Propagation was a segmented picker
  inside the scrolling content, Whois & GeoIP and Visual Traceroute were two
  filled buttons, and Network Monitor's strip changed height depending on what
  sat on its right. All four now use the same `ToolkitHeaderBar` + `AppTabBar`
  strip as Connections, and the strip's row has a fixed height, so captions and
  buttons no longer stretch it. Selecting DNS propagation in the sidebar or from
  a `lanfi://` link now opens that tab instead of leaving Lookup showing.

## 5.6.10 — 2026-11-21

### Fixed
- **The MTR chart is no longer an empty plot.** A route with a single replying
  hop drew nothing: a path that only moves is never stroked, and the one 5 pt
  dot was invisible against the grid. The plot now draws a dashed guide across
  the route's latency, a ringed marker per replied hop and the current average
  as a label, so a nearby target shows a readable chart instead of a blank card.
- While a run is in progress and the first round has not finished, the screen
  shows "Measuring the route…" with a spinner instead of the "watch a route over
  time" empty state, which read as "nothing is happening".

## 5.6.9 — 2026-11-21

### Fixed
- **The device shelf's filter, search and export sit on one row.** The filter
  picker had been pushed onto its own line with a stray divider and a fixed
  320–460 pt width, so it read as a separate section above the search it
  narrows. Filter, search field and the export menu now share a single row: the
  picker keeps its intrinsic width, the search field flexes between 180 and
  320 pt, and a clear button appears inside it while a query is typed.
- The shelf's warranty filter and metric read "Warranty" in Russian; the label
  is translated in all five locales.

## 5.6.8 — 2026-11-21

### Fixed
- **Tables read as tables again.** Every `AppTable` now draws a hairline rule
  between columns in the header and in each row, gives each cell horizontal and
  vertical padding instead of gluing text to the column edge, and paints the
  header band so it separates from the data. Header type moved from `caption2`
  to a 12 pt semibold `Theme.Typography.tableHeader`, so a header is legible and
  the same size in every screen.
- **Columns fill the card.** Each column used to take its minimum width while a
  trailing `Spacer` swallowed the rest, which left the columns huddled at the
  left of a half-empty card. `Models/TableColumnLayout.swift` now distributes the
  leftover space in proportion to the column minimums, so the table ends exactly
  at the card edge.
- **Columns can be resized.** Every column boundary is a 7 pt grab strip with a
  resize cursor; dragging it sets that column's width, and the other columns
  give up space down to their minimums before the table starts scrolling. A
  plain click on the header still sorts, and a column cannot be dragged below
  its declared minimum.

### Added
- `Tests/TableColumnLayoutTests` covers the fill, proportional, minimum, borrow
  and scroll cases of the width rules.

## 5.6.7 — 2026-11-21

### Fixed
- **The site-survey plan is drawable again.** Clicks on the plan never arrived:
  the screen relied on `SpatialTapGesture`, which silently delivered nothing, so
  choosing a tool, moving the pointer and clicking added no sample, wall, room
  vertex or predictive AP. The plan now handles clicks through a `DragGesture`
  with a movement threshold, which reports the point in the sheet's own
  coordinates — the same space the grid, heat and markers are drawn in.
- The plan is a sheet with its own frame: grid, heat, sample dots, walls, rooms,
  AP markers and the empty-plan hint are all positioned inside that frame, so the
  hint is centred on the plan, the statistics card and legend sit inside its
  corners, and nothing spills over the window edge.
- The main window is fitted to the screen on launch (`Views/WindowLayout.swift`,
  `WindowFitter`). macOS restored a frame taller than the display, which put the
  bottom of the plan — and its legend — off the screen.
- A single sample no longer paints the whole floor as excellent: heat cell
  opacity fades linearly with the distance to the nearest measured sample, so
  the colour stays where it was measured and far corners stay honest.
- Clicking in record mode with no captured network used to do nothing at all; the
  plan now says to start a Wi-Fi scan first.

### Changed
- **One plan tool at a time (`Models/SurveyToolMode.swift`).** Four independent
  booleans (wall, room, walk, predictive) replaced by one mode, so two tools can
  no longer be on at once with the click order deciding which one runs. The
  inspector shows all six tools as chips, the toolbar shows the current one as a
  menu, and switching tools clears half-drawn geometry.
- Missing translations for the plan tools, the blank-plan sheet and the plan
  tool label in all five locales.

## 5.6.6 — 2026-11-20

### Added
- **Global shortcut for Connections (P3.1).** Settings → General can record one
  shortcut that opens Connections from any app. It needs ⌘, ⌃ or ⌥, refuses
  combinations macOS or this app already own by name, and reports when another
  app took the combination — putting the previous shortcut back instead of
  leaving none. Nothing is registered until the user records one.
- `Models/GlobalHotKey.swift`, `Services/GlobalHotKeyCenter.swift` and nine
  tests, including a round trip through the real Carbon registration API.

### Changed
- The app's notification names moved from `Views/WiFiWorkspace` to
  `Utils/WorkspaceNotificationNames.swift`, because `Services` posts them and
  the shared test target compiles `Services` without `Views`.

## 5.6.5 — 2026-11-20

### Changed
- **One set of surface values (D1).** Fifteen screens still named their own
  radius or translucent fill; they now read `DesignToken.Radius` and
  `DesignToken.Surface`. `Surface.controlFill` and `Surface.dangerFill` were
  added so the search-field chip and the failure block stop carrying their own
  numbers.

### Added
- `Tests/DesignTokenLintTests` fails when a file in `Views/` (other than
  `Theme.swift`) hard-codes a corner radius or a role-named translucent fill,
  and `CONTRIBUTING.md` now documents that rule.

## 5.6.4 — 2026-11-20

### Changed
- **Remote helpers run under supervision (P4.2).** The remote capture (`ssh`,
  `scp`, cleanup) and the remote sensor scan now go through
  `SupervisedCommand`, so a hung ssh has a hard limit and is stopped with
  SIGTERM then SIGKILL instead of leaving the screen waiting forever. Both
  output pipes are drained while the child runs.

### Fixed
- A short command that finished during the readiness window was reported as a
  failed launch, hiding its own status and message.
- Reading stderr to end-of-file before stdout deadlocked once the child filled
  the unread pipe; a large `system_profiler` answer could hang the scan.

## 5.6.3 — 2026-11-20

### Added
- **Why this answer (P4.3).** The DNS screen now explains the shape of an
  A/AAAA answer: a fake IP in 198.18.0.0/15, an answer made only of private
  addresses, a zero TTL, several networks behind one name, and whether the
  system resolver returns the same addresses. The system comparison is a second
  query in the background; if it fails the note is simply absent.
- `DNSAnswerExplanation` with nine rules-level tests over recorded answers.

## 5.6.2 — 2026-11-20

### Added
- **Country and network for DNS answers (P4.3).** An A/AAAA lookup now shows
  where the returned addresses live and which network announces them, using the
  GeoIP client the Whois screen already uses. The annotation arrives after the
  records, is deduplicated, capped at four lookups per answer, and a failed
  lookup leaves the cell empty rather than hiding the record.

## 5.6.1 — 2026-11-20

### Added
- **DNS over TLS (P4.3).** The resolver comparison now includes Cloudflare and
  Google over DoT (RFC 7858) next to the UDP and DoH rows, so a network that
  rewrites port 53 can be told apart from one that also blocks the encrypted
  transports. TLS runs on port 853 with SNI set to the resolver's name, and the
  answers are parsed by the same wire parser the UDP path uses.
- `DoTFraming` length-prefix helpers with partial-read and multi-frame tests, an
  opt-in live probe (`LANFI_LIVE_TESTS=1`) and `DoTResolver.custom` for
  `tls://host`, `host` and `host:port`.

### Fixed
- The DoT exchange could be deallocated before its TLS handshake finished,
  leaking the continuation and hanging the lookup indefinitely. The session is
  now held for the duration of the request and its state handler is released
  when the answer arrives.

## 5.6.0 — 2026-11-20

### Added
- **NAT Test (P4.4).** A new Network Tools screen sends STUN binding requests
  from a single UDP socket to two public servers, so the router's mapping can be
  compared: two probes to the first server prove the mapping is stable, the
  third destination shows whether the router reuses it. It reports the local and
  external endpoints, whether the source port survived, latency per probe, and a
  verdict — no NAT, cone NAT, symmetric NAT or no answer — with a copyable
  report.
- RFC 5389 binding request/response codec (XOR-MAPPED-ADDRESS and the legacy
  MAPPED-ADDRESS, IPv4 and IPv6) and a pure classification model, both covered
  by `Tests/NATProfileTests`.
- Filtering behaviour is reported as "not probed" rather than guessed: proving
  it needs a server that sends back to the mapped address, which public STUN
  servers do not do.

## 5.5.9 — 2026-11-20

### Fixed
- **Copy in the DNS tool copies what is on screen.** With the resolver
  comparison open, Copy writes that comparison — every resolver, its transport,
  answer and time, failed resolvers included, then the verdict — instead of the
  previous single-lookup answer. Copy and Clear stay enabled in compare mode.
- **Tables use the full width of their card again.** `AppTable` gives its
  content a width floor from its container, so rows no longer collapse to their
  intrinsic size; horizontal scrolling still appears when the columns need it.

### Changed
- **Every dashboard block is clickable.** The whole card reacts on hover and
  opens its tool on a click — connection, internet, VPN/Wi-Fi/traffic/automation
  tiles, throughput, uptime, bands, channels and link automation — instead of
  only the button or corner link inside it.

## 5.5.8 — 2026-11-20

### Changed
- **Every card is the same card.** `appCardSurface` now takes `tint:` (fill at
  12%, hairline at 30%, both from `Theme.Surface`) and `strokeWidth:`. The last
  bespoke recipes moved onto it — Protocols band/status cards (gradients
  removed), Interfaces, Insights panels, Visual Traceroute cards, survey chips
  and window edges, the survey map frame, multi-floor plans, the Help banner,
  the QR placeholder and both settings rule editors — so no panel draws its own
  fill, radius and border any more. The QR canvas stays white on purpose.
- **Live capture runs under `SupervisedProcess`.** The osascript helper counts
  as started only when tcpdump writes its pcap header (which happens after the
  admin prompt and after BPF opens the interface), the whole run is killed past
  `startDelay + duration + 20 s`, and a cancelled prompt is still reported as
  such. A prompt left open or a wedged tcpdump now ends in an error instead of
  a frozen window.

### Removed
- The supervisor's restart policy, health probe, retry-with-fresh-arguments and
  per-attempt launch counter. The callers are one-shot, so relaunching a
  capture behind the user's back would duplicate a privileged prompt rather
  than repair anything; start/readiness/run-limit/kill is all that is left and
  all that is tested.

## 5.5.7 — 2026-11-20

### Added
- **Keyboard navigation in the ⌘K palette.** ↑↓ move a highlighted row (with
  wrap-around), Return opens it, Esc closes; hovering moves the highlight so
  the mouse and keyboard agree, and clicking a row still opens it. The arrow
  keys are intercepted with a local event monitor because the search field
  would otherwise move the caret.
- **Localized palette keywords.** Settings keywords are now one localized
  string per page in all five locales, so «анонимная статистика» finds Privacy
  and «бенчмарк резолверов» finds Diagnostics instead of only English terms
  matching. The English list stays in code as the fallback.

### Fixed
- The Settings sidebar's group headers ("Application", "Analysis",
  "Integrations") stayed English in a translated app; they are now localized in
  all five locales.

### Changed
- **Settings navigation from the palette no longer depends on a string
  selector.** `SettingsRouter` carries the requested page and `SettingsView`
  consumes it, so the page is selected even if the window was already open;
  macOS 14+ opens the window through SwiftUI's own `openSettings` action, and
  the old selector remains only as the macOS 13 fallback.

## 5.5.6 — 2026-11-20

### Added
- **DNS resolver comparison (P4.3).** The DNS tool has a **Compare** button that
  asks system, Cloudflare and Google over plain UDP and Cloudflare and Google
  over DoH at the same time, then shows one table: resolver, transport, answer
  and time. A status pill says whether the answers agree; agreement ignores
  record order and TTL, but an empty answer next to a populated one counts as a
  disagreement, which is how a rewritten port 53 usually shows up. Resolvers
  that fail are listed with their error and counted, not hidden.
- DNS-over-HTTPS transport (`DoHDNSClient`) parsing the `application/dns-json`
  shape into the same records the UDP client returns, with the DoH status code
  surfaced as an error instead of an empty answer.

## 5.5.5 — 2026-11-20

### Added
- **Supervised helper process.** `Services/SupervisedProcess.swift` gives a
  long-lived child a readiness probe with a timeout (never "the process
  exists"), one retry with freshly built arguments, a rate-limited automatic
  restart that only runs while a health probe agrees, and an idempotent
  SIGTERM→SIGKILL shutdown serialised so two callers cannot start or kill two
  children. Writing its tests surfaced a real bug — a child that exited during
  startup was reported as running and its exit was dropped — which the launch
  path now detects. The capture and remote-sensor helpers still use their own
  spawning and will move onto it next.

## 5.5.4 — 2026-11-20

### Changed
- **One theme file.** `Views/Theme.swift` is the single definition of spacing,
  radii, strokes, layout geometry, semantic typography, surface and border
  colours, control metrics and the palette. `DesignToken` and `AppPalette` are
  now aliases of it, so the values exist once while every existing call site
  keeps working; a new screen has nowhere else to look.
- **Panels stop drawing their own card.** `ToolkitCard` is a facade over
  `AppCard`, both section-label types share one style modifier, and buttons,
  icon buttons and menu labels take their height, padding, icon size and
  chevron from the theme. The toolkit's separate fill/radius/stroke recipe —
  the one that made toolkit cards and workspace cards look like two apps — is
  deleted, and the Recommendation card in Insights uses the shared surface.

## 5.5.3 — 2026-11-20

### Added
- **⌘K command palette.** Every available tool, every settings page and every
  Wi-Fi workspace panel is indexed once in `CommandIndex` (title, category,
  keywords, destination), so a new screen becomes searchable without touching
  the palette. Ranking prefers an exact title over a prefix, a substring, a
  keyword, the subtitle and the category, and eight tests pin that order and
  the coverage. Settings pages are reachable by what they hold rather than
  only by their tab name — "anonymous statistics" opens Privacy, "resolver
  benchmark" opens Diagnostics. `SettingsSection` moved to Models so the index
  and the tests share the sidebar's list instead of copying it.

## 5.5.2 — 2026-11-20

### Changed
- **Connections and Process Traffic sort from their headers, and the last sort
  menu is gone.** `AppTable` gained hierarchical grouping: a group row marks a
  section, the sorter orders sections by their header value and sorts each
  section's children among themselves, so expanding a group and sorting a
  column no longer interleave unrelated rows. Action columns can opt out of
  sorting, and a row click still expands or collapses a group. Deleting
  `TableSortControl` means every SwiftUI table in LanFi now sorts the same way.

## 5.5.1 — 2026-11-20

### Changed
- **Offline Capture sorts from its headers.** The beacon table and the two
  tables inside its sheets (captured clients and management-frame counters)
  moved to `AppTable`. The three local sort enums, their comparators and the
  `TableSortControl` menus are gone, so each column's title, sort value and
  cell come from one declaration and the header affordance matches the rest of
  the app. Connections and Process Traffic stay on native `Table`: their
  hierarchical rows need a tree-capable table that keeps a group next to its
  children while a column sorts.

## 5.5.0 — 2026-11-19

### Fixed
- **The standalone CLI no longer links Sparkle.** `lanfi-cli` excluded
  `Services/UpdaterController.swift`, so `lanfi-cli help` (and the release
  smoke test) runs from its own binary instead of aborting on a missing
  `Sparkle.framework`.
- **The Device Shelf no longer crashes on launch.** `AppTable`'s generic
  context-menu initializer delegated to a designated initializer with the same
  `selection:rowMenu:` labels, so overload resolution picked the generic
  initializer again and every table with a row menu recursed until the stack
  overflowed. The designated initializer now uses distinct labels; the shelf
  (and any future screen with per-row menus) renders normally.

### Changed (tables, batch 2)
- **Eight more screens sort from their headers.** Speed Test history, Roaming
  transitions, DNS propagation, Device Shelf, Client Analytics (both tables),
  Controller access points, Remote Sensor scans, Live Client Discovery and the
  LAN Scanner device list lost their `TableSortControl` menus and local
  comparators. The LAN Scanner derives its columns from `LANSort`, so the header
  and the sort values stay one list; the shelf keeps favourite, selection and
  the per-row menu through `AppTable`'s selection and context-menu hooks.
- **The overview shows gateway, MAC and DNS on every link.** Those facts sat
  inside the Wi-Fi branch of the Connection card, so they disappeared when
  Ethernet carried traffic; they now sit below it, always visible, and are not
  repeated in the metric tiles.

### Changed (sources and tables)
- **project.yml no longer lists shared files by hand.** The application, the
  `lanfi-cli` tool and the test bundle all take `Models`, `Services`, `Utils`
  (and `CLI` where relevant) as folders, so a new shared file is picked up by
  all three after `xcodegen generate` and cannot desynchronise them. The
  `SharedToolchainSources` template and the ~90-line test source list are gone;
  both targets now also declare the Sparkle package they already imported.
- **Header sorting reached five more screens.** Port Scan (TCP and UDP), HTTP
  Traffic, iperf3 history, Uptime checks and the Network Monitor routing table
  moved to `AppTable`; their `TableSortControl` menus, local sort enums and
  comparator functions are gone. `AppTable` gained a row selection binding and a
  context-menu initializer, so HTTP Traffic keeps its inspector and row choice.

### Changed (overview and guards)
- **The overview is a dashboard, not a stack of equal boxes.** It leads with the
  link and the internet verdict side by side (signal, quality, channel and
  security next to latency, public IP and the check time), then four equal
  metric tiles (VPN, Wi-Fi, traffic today, automation), live throughput next to
  uptime, the band and channel picture, and a three-column quick-action grid
  whose buttons all fill their cells. Gateway, DNS verdict and MAC live under
  the connection instead of in a separate tile.
- **The overview no longer needs the app environment to exist.**
  `NetworkToolkitView` and `OverviewDashboardView` take the meter as an explicit
  parameter defaulting to the one shared `MenuBarMeterModel`, so previews, the
  snapshot harness and the smoke test cannot crash on a missing
  `@EnvironmentObject` and no second sampler is created.
- **GatewayGuard and VPNGuard share one polling layer.** `PollingGuard` owns the
  timer, its tolerance, the overlap guard and the `isSampling` /
  `lastCheckedAt` flags; `SecurityEvent.post` is the single event channel and
  `ShellOutput.run` the single off-main shell read. Each guard now only answers
  its own question in `performSample()`.

### Fixed
- **Opening Terminal no longer freezes the window.** The `osascript`
  hand-off runs off the main actor, so the first Automation permission prompt
  cannot block the UI; a refused or failed request now reports the message in
  Remote Sensors and in the LAN Scanner context menu.

### Added
- **Connectivity watchdog in the menu bar.** LanFi now checks whether the
  internet actually works, not just whether Wi-Fi is associated. An
  `NWPathMonitor` plus a timed probe (default
  `http://captive.apple.com/hotspot-detect.html`, configurable fallback) report
  **online**, **captive portal** or **offline**, the menu-bar icon changes when
  the WAN drops, and the latency metric uses the live sample instead of the last
  diagnostics run. One failed probe never flips a healthy connection, a captive
  portal is labelled as such rather than as offline, and transitions notify with
  per-direction toggles that honour the Wi-Fi Monitor quiet hours. Configure the
  interval (15 s–5 min), probe URLs and notifications in Settings → General, or
  ask Shortcuts for the current state.

### Added (listener watch)
- **Connections lists UDP listeners and watches the listener set.** The Sockets
  table gained an **Include UDP listeners** toggle, the transport in the Proto
  column and an **Exposure** column that labels every local endpoint as local
  (loopback), all interfaces or LAN-reachable. "Watch listeners" samples `lsof`
  every 30 s and posts one notification per new or closed listener; the first
  sample is a baseline, so turning it on does not announce every server that
  was already running. LAN-reachable is deliberately not called "public":
  LanFi cannot see your router's port forwarding.

### Added (SSH quick launch)
- **Open a saved sensor or an SSH-capable LAN device in Terminal.** The Remote
  Sensors sidebar and header offer "Open in Terminal" and "Copy SSH command",
  and a LAN Scanner device with port 22 open gets the same two actions in its
  context menu. The command is built from the sensor's host, user, port and key
  path and fully quoted for the shell; LanFi never reads the Keychain, never
  types a password and never creates a key.

### Added (service descriptions)
- **Plain-language service names.** Connections gained a Service column and the
  HTTP traffic screen a Service column plus an inspector row, so
  `gateway.icloud.com` reads "Apple push notifications" and
  `com.apple.WebKit.Networking` reads "Web content hosted by an app". The map
  ships offline (43 domain patterns, 18 process names, exact before suffix), an
  unknown name reads "Unknown service" with the raw host one copy away, and on
  macOS 26 the opt-in on-device model can label unknown hosts locally.

### Added (gateway and DNS integrity)
- **Gateway ARP and DNS-hijack detection.** Every two minutes LanFi re-reads the
  default gateway's hardware address from the ARP table and posts a critical
  "Gateway MAC changed" event if the IP stays the same but the MAC does not —
  the classic ARP-spoofing signature. Every ten minutes it compares the system
  resolver's answer for a canary host with Cloudflare's direct answer and raises
  a warning-level "DNS answer mismatch", explicitly labelled as a warning
  because CDNs vary by resolver. Both feed the Monitor log, quiet hours and the
  Security Watch screen, each with its own alert toggle; the guard is on by
  default and can be switched off in Settings → General.

### Added (VPN and leak indicators)
- **VPN state and leak indicators.** LanFi now detects an active tunnel from the
  local route table and up `utun`/`ipsec`/`ppp` interfaces, and shows two
  indicators on the Security Watch screen: a DNS leak when the resolver in use
  is not one the tunnel pushed, and an IPv6 leak when a global IPv6 default
  route leaves through a non-tunnel interface. An unexpected drop and a new leak
  raise "VPN dropped" / "Possible VPN leak" Monitor events, each with its own
  alert toggle. Everything is a local read — no provider API, no credentials —
  and both indicators are explicitly labelled as indicators, not proof.

### Added (privacy and settings)
- **Privacy settings and a written policy.** Settings → Privacy carries the
  policy, a list of what LanFi never collects, and an **Allow anonymous usage
  statistics** switch that is off by default; when enabled, future builds may
  send anonymised counters (app and macOS version, which tools were opened, run
  outcome) with no SSIDs, addresses, host names, domains, paths or free text.
  Current builds transmit nothing. The full text ships as `PRIVACY.md`.
- **Toolkit settings.** Settings → Toolkit sets the default analysis target
  shared by every probe screen and manages the five-entry recent list, instead
  of leaving the value wherever the last tool left it.

### Added (resolver benchmark)
- **Compare DNS resolvers without switching them.** The DNS screen has a
  Benchmark card that resolves three names three times through the system,
  Cloudflare, Google and Quad9 resolvers, then ranks them by median lookup time
  and shows the range and failed lookups. It only measures: LanFi still never
  changes your DNS setting on its own.

### Added (Ethernet/Wi-Fi automation)
- **Turn Wi-Fi off while Ethernet is connected.** Off by default: when a
  physical Ethernet link comes up, LanFi turns Wi-Fi off once and restores it
  once when the cable goes away, with a master pause, a notification per change
  and a Settings card showing the link, the Wi-Fi power state and the last
  action. It is edge-triggered, so a manual Wi-Fi change always wins.

### Added (overview dashboard)
- **The app opens on an overview, not on the Wi-Fi table.** A new default screen
  summarises what LanFi already watches: the connected network with signal and
  quality, internet reachability and latency, gateway and DNS integrity, VPN and
  leak state, today's traffic, networks per band with a stacked bar, the six
  busiest channels, a live throughput sparkline, the first uptime targets and
  quick actions into the analyzer, Ping, DNS, Speed Test, Connections and the LAN
  Scanner. It reuses the shared services — no second poller, no extra scan — and
  the Wi-Fi analyzer is now one tool among them.

### Changed
- **Whois and GeoIP are one screen.** Both answer questions about the same
  target, so they share a tab strip, one input (typed in either tab and mirrored
  to the other) and one sidebar row; a `lanfi://tool/geoip` deep link still
  opens the GeoIP tab.
- **MTR is the Continuous tab of Traceroute.** The map and hop table keep the
  Route tab, MTR moved next to them instead of a separate sidebar entry, and a
  deep link to MTR still lands on its tab. The now-unused classic
  `TracerouteToolView` was deleted.
- **One button, one header, one list row across the toolkit.** Every tool
  screen now draws its actions with `AppButton` (plus `AppIconButton` for
  icon-only controls) and its header strip with `ToolkitHeaderBar`, so DNS,
  Ping, GeoIP, iperf3, the LAN Scanner, Uptime, Roaming and the connections
  screens share one control height, radius, stroke and padding, including the
  export, refresh, "check now", inspector and expand/collapse actions. Menus,
  context menus and confirmation dialogs keep native buttons, because a custom
  button style does not render inside them.
- **The DMG opens a folder instead of an installer.** The disk image mounts a
  window with `LanFi.app` next to an Applications alias and two read-me pages,
  English and Russian, that explain dragging the app in and opening it despite
  Gatekeeper on an unsigned build (`Control`-click → Open, System Settings →
  Open Anyway, `xattr -dr com.apple.quarantine`).
- **Help no longer ships screenshots.** The topic pages use a symbol banner and
  the existing caption, so the manual cannot expose anyone's SSIDs, addresses
  or device names.

### Fixed
- **Whois events, Path Check ports, the TLS chain and DNS answers sort from the
  column header.** Those four tables moved from `Table` + a separate
  `TableSortControl` menu to `AppTable`, so the sort menu is gone and the header
  behaves like the rest of the app.
- **The refresh-interval menu stays open.** The countdown used to re-lay out its
  label twice a second while the native menu was tracking, which made the list
  jump and could dismiss it. The control is now a button with an explicit
  popover: the `TimelineView` stops while the list is open, the figure is whole
  seconds in a fixed-width monospaced slot, and a chevron plus a hover tint keep
  the element looking clickable.
- **Enabling Ethernet/Wi-Fi automation now asks for notification permission.**
  The feature's only output is a banner, so turning the switch on requests
  authorization once, and a refused prompt shows an inline warning with a
  shortcut to Notification settings instead of switching Wi-Fi silently.
- **Signal and quality bars no longer squeeze their label.** The bar width is
  computed from the measured text width (`SignalBarMetrics`, capped at 60% of
  the column, 12 pt minimum bar) instead of `intrinsicContentSize`, which
  returns -1 before layout and the pre-truncation width after it — the value
  stayed legible in a narrow inspector column and the bar grew back in a wide
  one. Covered by five unit tests.
- **The shared target history now records every run, not just Return.** Ping,
  Traceroute, MTR, DNS, Whois, GeoIP, Port Scan, TLS, Path Check and iperf3
  store the address they probed, so the Recent menu fills up no matter how the
  run was started; the field shows a labelled "Recent" control instead of a
  lone clock glyph.
- **MTR plots its hop chart again.** Average latency is a line and packet loss
  bars on one hop axis, drawn on a Canvas instead of the Swift Charts view that
  came out empty.
- **Site Survey accepts taps on the plan again** (samples, walls, rooms, access
  points, calibration) via `SpatialTapGesture`; the coverage heat grid is built
  once per change on a background task, with a "Computing coverage…" note while
  it runs.

### Changed
- The analyzer's countdown pill is now a working menu: it sets the scan
  interval (1, 3, 5, 10, 30, 60 s), opens the custom-interval sheet, and pauses
  or resumes auto-scan, instead of being a read-only label.
- `MonitorNotifier` is the single shared notification delegate; the connectivity
  watchdog posts through it instead of installing a second one.
- **Traceroute and Visual Traceroute are one screen.** The map view now carries
  the classic controls (probes, timeout, resolve names) plus a sortable hop
  table — address, hostname, latency, location — and the separate Traceroute
  entry is gone from the sidebar.
- **Window minimum raised to 1160 × 700** so the sidebar, table and inspector
  fit together, and **LAN Scanner now shows device names** learned from reverse
  DNS. On the Devices tab the All / In network / Favourites filter sits above
  the search field.

## 5.4.0 — 2026-11-18

### Changed
- **One analysis target across the whole toolkit.** The address you type in
  Ping, MTR, Traceroute, Visual Traceroute, Port Scan, TLS, DNS, GeoIP, Whois,
  Path Check or iperf3 is now shared by every tool, and each field remembers the
  last five submitted values in its drop-down. Type `example.com` once and open
  another tool to use it without retyping.
- **DNS Lookup and DNS Propagation are one tab.** The DNS screen gained a
  Lookup/Propagation switch; both sections share the analysis target and the
  resolver table, instead of living as two sidebar entries.
- **One traceroute engine.** Visual Traceroute no longer runs its own ICMP
  stream with a UDP retry; it uses the same `SystemTracerouteRunner().trace`
  call as the plain screen, which is the path that resolved a single host
  reliably. Both screens can copy the hop list, and the visual list includes
  the city/country for public hops.
- **Connections group by application.** Renderers and helpers of one app now
  share a row instead of appearing as separate applications, a click anywhere
  on a group row expands or collapses it, and every table row has a context
  menu (copy, block rule, terminate). The Rules tab is aligned to the top like
  the other two tabs.
- **LAN Scanner layout and device details.** The All/Online/Favourites filter
  moved to its own line so it no longer overlaps the search field; the device
  table gained a Hostname column, and right-clicking a device offers rename,
  copy name/IP/MAC/details, Wake on LAN and Forget.
- **Shared table sorting.** `Views/TableSorting.swift` adds `SortValue`,
  `SortColumn` and `TableSorter`, a single comparator and stable ordering used
  by the LAN Scanner and device shelf; the rest of the toolkit keeps using the
  same `TableSortControl` component.
- **`project.yml` stops repeating the shared sources.** The 67 model/service
  files that both the test bundle and the CLI compiled are declared once in a
  `SharedToolchainSources` target template.

- **The analyzer and the MCP toolkit are split into focused files.**
  `AnalyzerViewModel` keeps dependencies, published state and initialisation in
  a 279-line core file; scanning, filtering, workspace queries, sessions,
  export and persistence live in six extensions under `ViewModels/Analyzer/`
  (125–383 lines each). `MCPToolkit` keeps the catalogue and handler switch in
  73 lines, with definitions, argument helpers, scan analysis, probes, service
  tools and shared encoding in five extensions.
- **One registry for view routing and MCP specs.** `ToolDescriptor` now carries
  `screen: ToolScreen` and `mcpTools`, so the detail screen switches on a route
  instead of raw tool ids (Sockets and Traffic share `.connections`) and the
  MCP catalogue lives in `MCPToolRegistry` (`Models/MCPToolSpec.swift`) instead
  of the CLI handler. New tests check every tool has a route, every screen is
  reachable, sidebar entries do not collide, every listed MCP name exists, and
  every advertised spec is well formed.

### Added
- **Every preference is a typed setting.** `AppSettingsKey` in `LanFiCore` is
  now the single catalogue of the 73 persisted keys, so no call site spells a
  `LanFi.*` string any more. `AppSettings` gained typed sections for scanning,
  alerts, monitor, capture, survey, reports, MCP, automation, display,
  interface and layout, each migrated from its legacy key and mirrored back so
  `@AppStorage` readers stay live. Values an older screen still writes directly
  are re-read before every save, so changing the theme no longer rolls back a
  report or MCP setting; import stays authoritative.
- **Dependency seams and a Swift 6 core.** `LanFiCore` now compiles in the
  Swift 6 language mode with an injectable clock, settings storage,
  notification poster and file store, and `AppSettingsStore` gained
  `export(to:)`/`importSettings(from:)`. The app mirrors the pattern: the
  analyzer takes any `WiFiScanning`, the monitor takes a clock and any
  `MonitorNotifying`, on top of the existing `UserNotifying` seam.
- **Connections became a firewall console.** Sockets group by local endpoint
  or process, Traffic groups by app or process, both with disclosure rows, and
  every row can terminate its owning process (SIGTERM, own processes only) or
  create a local block rule by application, process, PID, port, remote host or
  user. Rules are persisted in `~/Library/Application Support/LanFi/` and mark
  matching sockets; LanFi installs no packet filter or root helper, and the
  screen says so. The tool now lives under Monitoring, not Network Tools, and
  gained a Rules tab.
- **Sortable columns everywhere.** Every toolkit table — DNS answers and
  propagation, port scan (TCP and UDP), path check, traceroute, MTR, ping,
  TLS chain, uptime checks, speed-test and iperf3 history, Whois events, HTTP
  requests, roaming transitions, routing table, client analytics, live client
  discovery, remote sensors, controller access points, and offline capture
  beacons/clients/security — now exposes all its columns through the sort
  control. The comparison grid and Offline Capture's management table sort from
  clickable headers.
- **Seeded screenshot harness.** `scripts/visual-check.sh` now launches the
  Debug snapshot harness with `--demo`, which seeds deterministic Wi-Fi,
  survey and uptime fixtures (`Utils/DemoData.swift`, Debug-only, never
  written to disk) and blocks live scans, so screenshots no longer depend on
  Location access or the reviewer's network. It also captures the README/site
  gallery at a fixed 1180×760 pt window and exports `docs/images/*.webp` plus
  `site/assets/*.webp` with cwebp (ffmpeg fallback).
- **Task-oriented Help.** The Help window now answers six "what do you want to
  do" questions — first scan, inspect connections, diagnose a slow link,
  measure coverage, find the app using bandwidth, and set up/automate — instead
  of listing product areas. Each topic opens with one bundled screenshot of the
  screen it uses (`Resources/help-*.png`, captured in English from the snapshot
  harness) and task steps; search matches titles, steps and screenshot captions
  in both English and Russian.
- **Chart explainer.** The All Bands chart has a "What is this?" popover that
  decodes bar width, height, overlap shading, the recommended-channel marker and
  click-to-select, using the same swatches as the legend.
- **Passive and directed scanning (P0.2).** A scan-mode picker adds monitor-mode
  passive listening and per-channel directed listening beside the normal active
  scan. The plan is 6 GHz aware: PSC channels come first, Reduced Neighbor
  Report channels are promoted ahead of a blind sweep, non-PSC 6 GHz channels
  that active scans skip are included, and 6 GHz entries are labelled LPI/SP
  while 5 GHz DFS entries are marked. The sheet shows dwell per channel, total
  sweep time, live progress and an explanation when Apple N1 hardware cannot
  switch channels reliably. Passive rows merge into the same table, history and
  analysis as active scans.
- **All-band RF overview.** A new bottom-panel tab draws every nearby access
  point as a frequency span on 2.4, 5 and 6 GHz side by side, shades the
  regions where two or more networks collide and marks the recommended channel
  for each band; clicking a span selects the network. Fresh installs open on it,
  existing layouts keep their stored tab.
- **Design tokens.** Shared spacing, radius, stroke and semantic colour tokens
  plus `AppCard`, `SectionLabel`, `StatusPill`, `StatTile` and `BandChip`. The
  RF overview is the first screen built on them.
- **Menu-bar live meter.** The menu-bar item can show a Canvas sparkline of the
  last 60 throughput samples, a live number (throughput, signal, quality or
  latency) or the icon alone, in bit/s or byte/s. The popover adds a throughput
  block, a connected-link block with band, channel and width, a latency strip
  from diagnostics, an on-demand public IP with country, and the existing
  alerts and uptime rows. Counters come from `getifaddrs` for the primary and
  Wi-Fi interfaces and the sampler slows to one tick every 30 s in the
  background.
- **Table presentation.** Compact/standard/roomy density now drives the AppKit
  row height and cell font; signal and quality cells paint a colour bar in its
  own gutter beside the number (never underneath it), and the header marks the
  active grouping. Band and security stay text-only.
- **Column-driven sort menu.** The sort menu is generated from the visible table
  columns in column order and skips identity columns (network name, BSSID, AP
  name, annotations), so new and renamed columns appear without a second list.
- **Single sort indicator.** The header no longer appends its own arrow; only
  AppKit's sort indicator is shown.

- **Signal history shows noise.** The history chart has a Signal / Noise /
  Both switch; noise is dashed so it never competes with the signal trace and is
  hidden in percent mode, where it has no meaning.
- **First run and empty states.** A fresh install opens on one screen explaining
  what LanFi shows, why macOS needs Location Services and that nothing leaves
  the Mac. The workspace now names its state instead of showing an empty table:
  no scan, no networks, no permission, no Wi-Fi hardware, failed scan, stale
  data or over-filtering, each with the action that fixes it.
- **Why a network is hard to see.** The inspector explains 6 GHz PSC and
  non-PSC channels, DFS sharing and hidden SSIDs, and lists the other radios of
  the same access point when LanFi infers them.
- **Chart style tokens.** `ChartStyle` now defines the axis, grid, cursor and
  tooltip look used by the history and occupancy charts.
- **Roaming Test.** A new Wi-Fi tool shows the connected BSSID's 802.11k/v/r
  support, the BSSID transitions and failed roams from the Wi-Fi Monitor, and
  sticky-client and band-steering verdicts. A walk test starts a fresh window.
- **Known Networks and Wi-Fi QR.** The toolkit lists the network names saved in
  System Settings (names only — never passwords), shows which are in range, and
  turns a user-typed password into a guest QR code.
- **Shortcuts and App Intents.** Scan summary, connected network and speed test
  are available to Shortcuts, with suggested phrases.
- **Link inspector block.** The inspector starts with the live connected link:
  transmit rate with min/avg/max over 60 samples, channel and width, noise, PHY
  and the beacon's NSS capability (labelled as capability, since CoreWLAN does
  not expose live MCS/NSS).
- **Combined report.** `Data → Export Combined Report…` writes one HTML file
  with the scan and quality, survey summary, security findings, diagnostics,
  recent speed tests and monitor events.
- **6 GHz power mode.** The HE Operation element's 6 GHz Operation Information
  is decoded, so a 6 GHz network now shows whether its AP runs Low Power Indoor,
  Standard Power or Very Low Power (regulatory info is domain-dependent; the
  labels follow the US/FCC meaning).
- **Security Watch.** A new Wi-Fi tool flags a possible evil twin (one BSSID of
  an SSID open/WEP while another uses WPA2 or better, unless the radios are
  proven co-located), security downgrades to legacy WPA, randomized BSSIDs next
  to registered hardware, and deauth bursts observed by a packet capture in the
  last 15 minutes. Read-only heuristics with an "Open Capture" action; macOS
  offers apps no passive deauth feed.
- **Reduced Neighbor Report.** Element 201 is decoded into neighbour operating
  class, channel, BSSID, short SSID, BSS parameters, 20 MHz PSD and MLD
  parameters, listed in the raw IE view.
- **One toolbar treatment.** `ToolbarIconButton` and `appToolbarChrome` give the
  Wi-Fi workspace and the toolkit header the same control height, radius,
  stroke and icon+label rule; refresh/pause, settings, export, inspector,
  diagnostics, location and Help use them.
- **Scanning interface label.** The workspace toolbar shows
  "Scanning with <interface>" beside the scan controls, resolving the
  Settings → Wi-Fi choice or the system default to match the scanner.
- **Sparkline geometry.** The menu-bar sparkline is drawn from the pure
  `SparklineGeometry` and shared `ChartStyle` sparkline tokens and covered by
  geometry tests.
- **Per-network speed-test history.** Each speed test records the connected
  SSID/BSSID and the History tab groups tests by network with a picker, latest
  down/up, latency delta, averages and bufferbloat grade. Older history entries
  without a network still load and appear as "Not recorded".

### Changed
- **Menu-bar label legibility.** The `MenuBarExtra` label renders monochrome as
  a template image and VoiceOver reads one combined label instead of separate
  glyphs.
- **Icon audit.** Icon-only controls in the chart toolbars, filter bar,
  spectrum/history zoom, device shelf, remote sensors, uptime, controllers and
  notification banner now carry tooltips and accessibility labels, and the
  toolkit status tones follow the semantic palette.
- **One chart language.** The Canvas spectrum uses the shared chart tokens for
  its grid, labels, hover cursor and readouts, and the Uptime and Ping latency
  charts share the same axes as the history charts.
- **Pinned Link block.** The inspector keeps the live Link block above the
  scrolling detail sections and adds cipher and BSSID to it.
- **Menu-bar Open.** "Open LanFi" now lands on the all-band RF overview.

### Added
- **802.11 IE decoder depth.** Extended BSS Load (193) reports MU-MIMO station
  count, stream underutilization and secondary 20/40/80 MHz utilization;
  Multiple BSSID (71) lists non-transmitted profiles and their BSSID indices.
- **Distribution guide.** `DISTRIBUTION.md` documents why ad-hoc updates can
  reset Location Services and how to recover, plus the signing/notary checklist.
- **Colour-blind-friendly palette (D7).** Settings → Appearance switches
  status, quality and band colours to the Okabe–Ito blue/amber/magenta set,
  with a live swatch preview.
- **MCP actions for the new tools (P1.6).** `lanfi_client_analytics`,
  `lanfi_survey_plan` and `lanfi_open_connections` join the CLI catalogue, with
  schema/definition and handler tests; the CLI target now compiles the shared
  analytics, survey and connection models.
- **Accessibility labels (D7, partial).** Shared status pills, metrics and tab
  bar expose combined labels; Survey's icon-only controls and the GPX map have
  explicit VoiceOver labels and values.
- **Open Connections (P1.8).** Read-only `lsof -nP -iTCP` inventory: process,
  PID, user, protocol, local/remote endpoint and state, optional listening
  sockets, filtering and copy. No shell, no privileges, no telemetry.
- **Client Analytics (P1.3).** Per-AP advertised client load, channel
  utilization, optional monitor-captured clients (MAC/vendor/frames/RSSI/probes)
  and plain-language insights. New Wi-Fi toolkit tool with tests.
- **GPS survey map (P1.9).** Import/export GPX walks, optional per-sample
  latitude/longitude, a MapKit sheet with track and sample markers, and tagging
  the newest sample with the current (Wi-Fi-derived) location.
- **Survey Planning 2.0 + Active Survey (P1.4).** Free-space AP layout planning
  with a coverage estimate and one-click placement, plus a gap grid, next-target
  hint and completion percentage for the walk-through.
- **Launch at login and updates.** General settings gained `SMAppService` login
  item control, Sparkle auto-check toggle, last-check time, release notes and
  Homebrew helpers.
- **Design system.** Shared `appSheet`, `AppSheetHeader`, `AppColumnWidth` and
  `appTableSurface` replace per-screen sheet sizes, table surfaces and column
  widths; settings now use reusable cards and spacing tokens.

### Changed
- **Settings sidebar.** Settings moved from eleven tabs to a grouped sidebar;
  the last section is remembered.
- **Live row density.** The row-density setting now drives one shared table
  style across the toolkit and Settings through a live `@AppStorage` modifier;
  no relaunch is needed.
- **One tab strip.** The Wi-Fi workspace's bottom tabs now use the reusable
  `AppTabBar`, so tab type, spacing and selection styling have a single source.
- **Known Networks detail.** Saved networks are selectable rows with a detail
  pane (live radio details or a "not in range" explanation); the guest QR sheet
  was rebuilt so the code, fields and payload fit without clipping.
- **Blank survey plans.** Site Survey can now create an image-less plan from
  real metre dimensions and draw on a labelled grid, instead of requiring an
  imported floor-plan image.
- **GPX route drawing.** The survey map now renders imported/bundled GPX walks
  as a real MapKit polyline with coloured RSSI markers, a bundled demo walk and
  current-location tagging.
- **Column-aware bars.** Signal and quality bars scale with their column width
  and the number sits directly beside the bar, closing the gap in wide columns.
- **Unified tabs.** LAN Scanner and survey planning now use the same `AppTabBar`
  as the Wi-Fi workspace; the old segmented and private tab styles are gone.

- **Relative seen times.** First Seen and Last Seen read "5 minutes ago" under
  a day and fall back to an absolute date-time after that.
- **SSID overhead in the inspector.** Beacon airtime as a share of airtime is
  now visible in the inspector's technical specs, not only as a column.
- **Column header tooltips.** Every column explains its domain terms in plain
  language (BSS Load, PMF, puncturing, wide channels).

### Changed
- **Roadmap.** The November gap analysis now includes a design and presentation
  track (tokens and shared components, all-band RF overview, table density,
  menu-bar meter) and new items taken from a review of NetWorker Pro,
  AirRadar 8, PeakHour 6 and an Unstore buyer's guide, recorded in
  `docs/REFERENCE_APPS_REVIEW_2026-11.md`.

## 5.3.0 — 2026-11-15

### Added
- **Wi-Fi Monitor.** The Wi-Fi workspace now keeps a rolling monitor for the
  connected link and all visible access points: 1 h / 24 h / 7 d / 30 d
  retention, RSSI timeline, min/avg/max/p95, peer aggregates, CSV export and a
  before/after comparison for 1 h / 6 h / 24 h.
- **Monitor events and alerts.** Connect, disconnect, roaming, channel change,
  security downgrade, PMF loss, WPS enabled and weak-signal crossings are
  recorded. Optional macOS notifications support per-kind toggles, quiet hours
  (including overnight), a cooldown and foreground banners.
- **Access point grouping.** Scans can be grouped by advertised AP name so the
  2.4/5/6 GHz radios of one AP collapse into a single group; unnamed radios stay
  separate BSSID groups.
- **History statistics.** Signal and utilization inspectors show min/avg/max/p95
  for the rolling window.
- **Typed settings export/import.** General, display and toolbar preferences
  are stored as a typed `AppSettings` model and can be exported or imported as
  JSON. Legacy `LanFi.*` keys are written through for compatibility.

### Changed
- **Faster scans.** Custom OUI overrides are cached, the analyzer indexes
  networks by band and id instead of rescanning the full list, and rolling
  history is published once per scan instead of once per network.
- **Toolkit structure.** `ToolkitViewModel` is split into 15 focused tool-model
  files; tool metadata now lives in one `ToolRegistry` table.
- **Build structure.** The first local SwiftPM module, `LanFiCore`, now owns the
  typed settings store and runs its own `swift test` suite. CI runs the core
  tests and `swift-format` is blocking.

### Fixed
- Monitor alerts are presented while LanFi is frontmost.
- Older `monitor.json` files without peer or PMF/WPS fields decode instead of
  discarding history.

## 5.2.0 — 2026-11-14

### Added
- **Asset register in the Device Shelf.** Each device now carries a serial
  number, location, purchase date and warranty end, editable in the inspector.
  The shelf derives the warranty state from the single date, flags devices that
  expire within 30 days (or already have), and adds a Warranty filter, metric
  and table column. CSV, JSON and `lanfi_devices` exports include the fields.
- **Printed device labels.** Every device gets an opaque `LF-…` asset tag on
  first sight; a QR label sheet (PDF) and single PNG codes encode
  `lanfi://device/<tag>` instead of a MAC address, and opening such a link
  selects that device on the shelf.
- **Wake-on-LAN.** The shelf sends a standard magic packet to any device with a
  known MAC.
- **HTTP Traffic analysis.** A new Network Tools screen reads a HAR archive
  exported by browser DevTools, Proxyman, Charles or Rockxy and reports the
  slowest requests, failures, p95 latency, transferred and uncompressed bytes
  per host, cache hits and the dominant timing phase. LanFi analyzes the
  recording only — it does not proxy, intercept or decrypt traffic.
- **Shareable HTTP reports.** Copy any request as a cURL command, export CSV or
  a Markdown report; `lanfi-cli har` and the `lanfi_har` MCP tool expose the
  same analysis to scripts and agents.
- **Credential redaction.** Authorization, cookie and token values are masked
  in exports, the inspector and copied cURL commands, and JSON bodies lose
  password/token fields, while the loaded capture stays untouched.
- **Capture security audit.** Offline packet analysis now decodes EAPOL-Key
  frames and reports, per BSSID, whether a 4-way handshake or a PMKID is in
  the capture and whether the network is still offline-crackable. Findings use
  the same graded severity as the live security audit, appear in the beacon
  table, a dedicated Security sheet, JSON/CSV exports and `lanfi_capture`.
- **Management-frame counters.** Deauthentication and disassociation frames are
  counted per BSSID with their 802.11 reason codes; a burst within five seconds
  is flagged as a possible management-frame flood. Beacon floods with many
  randomized BSSIDs on one SSID are reported too.
- **Richer capture clients.** The client list shows OUI vendor, best RSSI,
  last-seen time, management/data frame mix, EAPOL activity and the SSIDs each
  client probed for, can be filtered to the selected network, and matches MACs
  against the Device Shelf.
- **Channel plans for capture profiles.** Profiles store a channel list, and the
  live capture form fills it from 2.4/5/6 GHz band buttons or a comma-separated
  list; one channel pins the interface.

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
