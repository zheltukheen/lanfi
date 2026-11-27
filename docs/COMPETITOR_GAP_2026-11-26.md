# Competitor gap analysis — second pass, 26 November 2026

Status: **active backlog**. Baseline: LanFi 5.6.34 (build 117). G1, G2, G4, G4b,
G5, G6, G7, G8, G9 and G15 shipped on 2026-11-26/27 and are marked below; the
next slice is G10.

This is the second pass. [`COMMERCIAL_GAP.md`](COMMERCIAL_GAP.md) asked *"can we
sell this?"*; [`GAP_ANALYSIS_2026-11.md`](GAP_ANALYSIS_2026-11.md) asked *"what
did Netutilus, the menu-bar segment and one GPL app do that we do not?"*. This
document asks a narrower question: **what does the 2026 shipping competitor set
do that LanFi cannot, and which of those gaps are worth closing?**

Everything below comes from public product pages, documentation and release
notes read on 2026-11-26. Nothing was reverse-engineered, and no feature is
listed as a competitor's unless its vendor documents it. Where a claim is
hardware-bound (spectrum analyzers, USB adapters, cloud accounts) that is stated
instead of being folded into a software gap.

## Why a second pass

The first plan is 148 items closed and 5 open, all five external (signing,
helper, MAS). Three of the five "partial" items are large platform bets
(widgets, `LanFiCore`, live Wi-Spy). Meanwhile the paid market moved in the last
six months: WiFi Explorer Pro shipped PCAPNG export and restored passive scan on
the M5 Macs (3.10, June 2026), NetSpot shipped multi-floor planning (6.0, August
2026), Airtool gained Hamina Clip and iOS capture control, and the
validation/assurance segment (NetAlly Link-Live, Hamina, Sidos, eino, 7SIGNAL)
turned site surveys into pass/fail evidence with a cloud trail.

The useful question is therefore not "more features" but **which workflows
still force a LanFi user to open a second app**. Those are the gaps below.

## Segments and sources

| Segment | Products | What they sell |
| --- | --- | --- |
| Desktop analyzers | WiFi Explorer Pro 3.10, WiFi Explorer 3.6, inSSIDer 5, Acrylic Wi-Fi, WiFi Lens 1.6, NetSpot Inspector | Field depth, filtering, interpretation |
| Packet capture | Airtool 2, MetaGeek App, Acrylic Sniffer, `tcpdump` | Capture ergonomics and post-processing |
| Site survey / design | NetSpot 6, Ekahau AI Pro, Hamina, iBwave Design, Sidos, eino | Predictive design, validation, reports |
| Handheld validation | NetAlly AirCheck G3 Pro, EtherScope nXG + Link-Live | AutoTest, discovery, path analysis, cloud |
| Menu bar | WiFi Signal 4.5, NetWorker Pro, PeakHour (covered in the first plan) | Always-on connection telemetry |
| Assurance / AI | 7SIGNAL, Mist, Hamina Live, WiFi Lens Pro | Sensors, reliability scoring, agent access |

Products deliberately left out: Windows-only scanners with no macOS path, iOS
and Android field apps (WiFiman mobile, NetSpot mobile) beyond what they say
about desktop parity, and hardware that LanFi cannot drive (Ekahau Sidekick,
Oscium WiPry, Wi-Spy Lucid) — the hardware blocker is already recorded as P2.1.

## Capability matrix

Legend: ✅ shipped, ◐ partial, — absent. "LanFi today" is verified against the
code and `CHANGELOG.md`, not against the marketing table.

| Capability | Who documents it | LanFi today | Verdict |
| --- | --- | --- | --- |
| Active / passive / directed scan | WiFi Explorer Pro, inSSIDer | ✅ P0.2 | parity |
| Custom column profiles and coloring rules | WiFi Explorer Pro, LanFi | ✅ 48 columns, `ColoringRule` | parity in kind, behind in depth |
| Add any decoded 802.11 field as a column | WiFi Explorer Pro (850–950 fields), LanFi | ✅ decoded-field catalogue, field-backed columns, all-fields CSV | delivered (depth grows per decoder) |
| Import another tool's scan (CSV/JSON) | WiFi Explorer Pro (AirPort Utility, Aruba Utilities, Analiti, Mobile Eye) | ✅ vendor aliases, units, frequency-only files, unmapped-column report | delivered (G4b) |
| PCAP / PCAPNG export and offline analysis | WiFi Explorer Pro 3.10, inSSIDer | ✅ | parity |
| Capture with profiles, BPF, trigger, auto-open Wireshark | Airtool 2, LanFi | ✅ (`CaptureProfile`, BSSID/delay trigger) | parity |
| Capture file rotation, size cap, frame slicing | Airtool 2, LanFi | ✅ size cap + post-capture slicing | delivered |
| Channel dwell control during capture, PSC-only 6 GHz | Airtool 2, LanFi | ✅ dwell hopping + PSC filter | delivered |
| Live capture streamed into Wireshark | Airtool 2, LanFi | ✅ tails the file into Wireshark | delivered |
| Multi-sensor / multi-adapter capture merged into one trace | Airtool 2, MetaGeek App, NetAlly | ◐ one remote sensor at a time | **G3** |
| Remote capture from a WLAN Pi over SSH | Airtool 2, LanFi | ✅ | parity |
| Automatic sensor discovery on the LAN | Airtool 2 | — (manual host) | **G3b** |
| Cloud upload of captures | Airtool 2 (CloudShark, Packets) | — | non-goal (privacy stance) |
| Named scan snapshots, diff between two scans | inSSIDer, NetSpot, WiFi Explorer, LanFi | ✅ named snapshots + diff + CSV | delivered |
| "A new AP appeared" indicator / environment baseline | inSSIDer, NetAlly discovery diff, LanFi | ✅ baseline with one-time alert | delivered |
| Per-BSSID airtime attribution ("my network or the neighbours?") | inSSIDer, MetaGeek App, Chanalyzer, LanFi | ✅ transmitter-side airtime per BSSID + insight | delivered |
| Legacy 802.11b presence on a channel | inSSIDer, Chanalyzer, LanFi | ✅ basic-rate flag, legacy data-rate count, column + inspector | delivered |
| Client inventory with capabilities from monitor mode | Acrylic, MetaGeek App, NetAlly | ✅ captured clients + capability card from association IEs | delivered (G8) |
| RSSI "radar" to physically locate one AP or client | WiFi Lens 1.6, Acrylic | ✅ smoothed RSSI locator on the captured BSSID, labelled signal guidance | delivered (G8b, not direction finding) |
| 20+ heatmap visualisations (SNR, noise, SIR, AP count, band) | NetSpot, iBwave, NetAlly AirMapper | ◐ measured RSSI heatmap + pass/fail overlay; SNR/noise live in the scan, not per survey point | partly delivered (G9), layers open |
| User-defined pass/fail validation profiles | NetAlly AutoTest, Sidos, Ekahau, iBwave, LanFi | ✅ per-floor profile (RSSI, throughput, latency) with PDF/HTML verdict | delivered |
| Network reliability score and problem history | WiFi Lens Pro | ◐ event log, statistics | **G10** |
| Spectrum recording and replay | WiFi Lens Pro, Chanalyzer | — (live sweep + CSV import) | **G11** |
| Continuous observation while the app is closed | WiFi Lens Pro | — (menu-bar app must run) | **G12** (blocked) |
| AP placement optimisation, capacity planning, BOM | Ekahau AI Pro, Hamina, iBwave | ◐ predictive placement, no optimiser/capacity/BOM | **G13** |
| Client roaming simulation in a plan | Hamina | — (live roaming test ships) | **G13b** |
| 3D building model from CAD, auto wall detection | Ekahau, iBwave, Hamina, Sidos | ◐ multi-floor, wall materials, antenna patterns | **G14** (scoped out) |
| Wired+wireless discovery with names, VLAN, switch port path | NetAlly EtherScope nXG | ✅ bridge/VLAN/LLDP port path over SNMP (no wired-side discovery of its own) | delivered (G15) |
| MCP / agent access to live data | 7SIGNAL, WiFi Lens, LanFi | ✅ MCP 2.0 with live actions | **ahead** |
| Menu-bar display pattern over many metrics | WiFi Signal (18 metrics) | ◐ 5 metrics, fixed formats | **G16** |
| Interactive browser report with clickable APs | Hamina, Link-Live | ◐ self-contained HTML + PDF | minor |
| Cloud collaboration and shared workspaces | Link-Live, Hamina, Ekahau Cloud | — | non-goal |
| Notarized distribution | WiFi Explorer Pro, NetSpot, WiFi Signal | — | already P0.1 |

## Gaps, in priority order

Effort: S ≤ a day, M ≈ 2–4 days, L ≈ 1–2 weeks of focused work. "Testable" means
the acceptance can be checked without hardware or a GUI session.

### G1 — Capture rotation, size cap and frame slicing (P0, M)

**Evidence.** Airtool 2 documents file-size limits, file rotation and automatic
frame slicing (data-frame payloads dropped), plus a channel dwell setting and
5/6 GHz band selection including PSC-only. MetaGeek App keeps a bounded
temporary capture directory and shows free space.

**LanFi today.** `LiveCaptureView` offers 10/20/30/60 s, one channel or "auto",
BPF, a start delay and a BSSID trigger. `LiveCaptureService` runs one `tcpdump`
for the whole duration and there is no size cap, no rotation and no slicing
(grep for `snaplen`, `-C`, `-G` returns only `PassiveScanEngine`'s `-s 0`).

**Why it matters.** A 60-second full-frame capture on a busy channel is easily
hundreds of megabytes, and every serious capture tool lets the user cap it. The
dwell/`PSC-only` half is what makes a multi-channel capture reproducible instead
of "whatever macOS did".

**What ships.** A `CaptureLimits` value (max MB, rotate every N seconds, keep at
most K files, slice data frames to N bytes), mapped onto `tcpdump -C`, `-G`,
`-W` and `-s`; a channel plan with dwell and PSC-only that drives the monitor
interface through the existing `PassiveScanEngine` channel list; the sheet shows
the estimated file size before starting; the analysis pass reports which files
belong to one session so `PcapPacketIndex` reads them in order.

**Acceptance.** A 10-minute capture with a 50 MB cap produces a numbered file
series, the analysis sees all of them as one capture, and a sliced capture keeps
every management frame while data frames are truncated. Pure tests cover the
argument builder and the session/filename grouping; the run itself needs the
admin prompt and is recorded as not exercised in CI.

**Delivered 2026-11-26.** `CaptureLimits` drives `tcpdump -C` and
`CaptureFiles.mergeParts` folds `<name>1`, `<name>2`… back into the named file
before anything reads it, so the single-output contract holds. Slicing runs
after the capture in `PcapDataFrameSlicer`, which rewrites only data-frame
`incl_len` (radiotap-aware, management frames untouched) and leaves pcapng
alone. Channel dwell is applied by `CaptureChannelPlan` from the app through
`CWInterface.setWLANChannel`, the same unprivileged call the passive scan engine
uses, and `CaptureChannelRef` keeps the band so channel 5 on 6 GHz is not
confused with channel 5 on 2.4 GHz. Duration now ranges 5–600 s.

Not delivered: a file-count ring (`-W`) and time-based rotation. Both would
rename or overwrite the single output the app depends on, and the size cap
covers the disk risk the feature exists for. The real run was not exercised here
(it needs the admin prompt and a monitor-capable adapter); tests cover the
command builder, part merging, slicing and the hop schedule.

### G2 — Live capture streamed into Wireshark (P0, S/M)

**Evidence.** Airtool 2 streams packets to Wireshark while capturing (no file on
disk unless asked) and supports remote live captures the same way.

**LanFi today.** Captures are written to a file and the file is opened in
Wireshark after the run (`autoOpenWireshark`).

**Why it matters.** Troubleshooting a roam or a deauth burst is interactive: the
engineer watches frames appear, then stops. Waiting 60 s for a file breaks that
loop, and it is the last reason to keep Airtool installed next to LanFi.

**What ships.** A `mkfifo` pipe as `tcpdump -w` target, `open -a Wireshark <fifo>`
or a `wireshark -k -i <fifo>` hand-off, with the existing supervised process
handling termination. Fall back to the file path when Wireshark is absent, and
say which mode is running in the sheet.

**Acceptance.** With Wireshark installed, frames appear during the capture; on
Stop, no partial file is left behind; without Wireshark the capture still writes
a normal pcap. The pipe hand-off cannot be verified headlessly, so the test
covers the command construction and the fallback decision.

**Delivered 2026-11-26.** `WiresharkLiveStream` launches `wireshark -k -i -` and
tails the growing capture file into its stdin every 250 ms. The privileged side
is unchanged and Wireshark never runs as root. Stop writes `<capture>.stop`,
which the root shell polls once a second, so the capture ends without a second
password prompt. Streaming requires Wireshark in `/Applications` or Homebrew; the
toggle is disabled with an explanation when it is missing, and the size cap is
disabled while streaming because the stream follows one file.

Not exercised here: an actual Wireshark session (needs the admin prompt and a
capture-capable adapter). The command builder, stop path and the
streaming/rotation exclusion are covered by tests.

### G3 — Multi-sensor capture, merged and annotated (P1, L)

**Evidence.** Airtool 2 captures from several adapters or sensors at once and
merges them into one pcapng with per-frame sensor annotation; MetaGeek App
recommends three adapters; NetAlly AirMapper aggregates walk data from handhelds
into Link-Live.

**LanFi today.** `RemoteSensorService` scans one sensor at a time and
`RemoteCaptureService` captures from one sensor at a time. `RemoteSensorsView`
has no "capture on all" action, and the pcapng writer emits a single interface
block.

**Why it matters.** One radio cannot see all channels at once. Multi-channel
capture is the difference between "we missed the roam" and "we caught it", and
LanFi already has the SSH transport, the sensor store and the supervised command
runner.

**What ships.** (a) A multi-interface pcapng writer: one IDB per sensor with an
`if_name`/`if_description` option, packets written with the matching interface
ID; (b) a sequential or parallel capture plan across saved sensors, merged on
completion; (c) the analysis pass surfaces the sensor name per client/deauth
event; (d) failure of one sensor does not discard the others.

**Blocked part.** Five or more simultaneous high-rate captures over one SSH
connection benefit from the privileged helper (P4.1) and are not promised here.

**Acceptance.** Two local pcapng fixtures with different interface blocks merge
into one file that Wireshark and `PcapAnalyzer` both read, with the sensor name
preserved on every packet; a missing sensor is reported as a partial result.

### G4 — Decoded-field catalogue (P1, M)

**Evidence.** WiFi Explorer Pro 3 advertises more than 850 (App Store) to 950
(marketing) fields, all selectable as columns; CSV export includes them.

**LanFi today.** 48 `ColumnId` cases plus an information-element table and
protocol blocks. Many decoded values (RNR neighbours, MLO links, WFA
capabilities, per-IE vendor data) exist in the inspector but cannot become a
column, a CSV field or a report row.

**Why it matters.** This is the most-cited reason to buy the paid scanner, and
LanFi has already done the expensive part: the decoder. The missing piece is a
field catalogue and a column backed by it.

**What ships.** A `DecodedField` model (key, label, group, value, unit) produced
from a `NetworkModel`; a `FieldCatalog` listing every field with a search box;
one dynamic column kind that renders a chosen field and one "export all fields"
CSV mode; the same catalogue feeds the report and MCP.

**Acceptance.** A network with RNR, MLO and vendor IEs exposes those values as
selectable fields; a CSV export contains one column per selected field; the
catalogue is unit-tested for stable keys and empty values.

**G4 delivered 2026-11-26.** `DecodedFieldCatalog` turns a `NetworkModel` into
stable-keyed fields (`radio.frequency`, `cap.basicrates`, `security.pmf`,
`sixghz.powermode`, `mlo.apmld`, `mlo.links`, `ie.element.221.0`, plus IE count,
country IE channels and every vendor IE), and a field exists only when the value
does. The “Decoded Fields” window searches them, shows the key and value, and
promotes one to a real table column (`field:<key>`), which renders through the
same cell path and the normal CSV export. “Export CSV (All Decoded Fields)…”
writes the union of keys with aligned empty cells. Covered by
`Tests/DecodedFieldTests`.

Not delivered: the catalogue does not yet feed the report or MCP, and
field-backed columns are not in the sort menu (sorting still keys off the 46
`ColumnId` cases). Field depth also grows only as fast as the decoder — this
closes the mechanism, not WiFi Explorer's 850-field count.

**G4b (S).** Extend `GenericScanImporter` header aliases to the foreign CSV
columns named by WiFi Explorer Pro (Aruba Utilities, AirPort Utility, Analiti,
Mobile Eye) and report unmapped columns instead of silently dropping them.

**G4b delivered 2026-11-26.** Headers are normalised (case, underscores, BOM,
extra spaces) and matched against an alias table for all four vendor exports;
cells may carry units (`-52 dBm`, `80 MHz`, `36 (5 GHz)`); a frequency-only file
derives the channel and band (2412 → ch 1, 5180 → ch 36, 5955 → ch 1 on 6 GHz).
`loadDetailed` returns the imported networks plus the columns or JSON keys that
matched nothing, and both the file and URL import paths show them in an
informational alert instead of a silent drop. Tests cover vendor headers, units,
underscored headers, frequency derivation, unusable files and JSON row keys.

### G5 — Named snapshots and scan diff (P0, S)

**Evidence.** inSSIDer stores snapshots and benchmarks networks over time;
NetSpot keeps up to 50 snapshots per zone; WiFi Explorer supports side-by-side
comparison of two networks.

**LanFi today.** `MonitorViewModel` keeps a rolling 180-sample window with
before/after comparison, and sessions can be saved. There is no *named* scan
snapshot that can be diffed later, and no "what changed since last Tuesday" view.

**Why it matters.** Every real troubleshooting story is comparative: after an AP
firmware update, after a channel change, before/after adding a mesh node. A
snapshot + diff is the cheapest way to make the existing history and analyzer
data answer that.

**What ships.** `ScanSnapshot` (timestamp, label, note, networks with their key
metrics) saved from the Data menu; a diff view listing added/removed BSSIDs and
changed channel/width/security/RSSI; CSV export of the diff.

**Acceptance.** Two snapshots taken around a channel change produce one added
row, one removed row and one changed row, and importing a snapshot restores the
table without a live scan.

**Delivered 2026-11-26.** `ScanSnapshot` keeps BSSID, SSID, band, channel,
width, security, signal, vendor and generation; `ScanSnapshotStore` writes
`scan-snapshots.json` in Application Support (same pattern as GPS trips). The
“Scan Snapshots” window (Data menu → Compare Snapshots…) picks A and B,
shows added/removed/changed with a 10 dBm signal threshold so ±3 dBm scan noise
does not bury real changes, and exports the diff to CSV. Saving from the menu
posts a notification that refreshes an already open window.

Not delivered: importing a snapshot back into the table (the first plan already
has session open/save for that) and a semantic “expected vs unexpected change”
verdict. The window was not opened in a GUI session here; the diff and store are
covered by `Tests/ScanSnapshotDiffTests`.

### G6 — Environment baseline and "new AP appeared" alert (P0, S)

**Evidence.** inSSIDer flags a new AP entering the environment; NetAlly's
Discovery Difference highlights changes as a security signal; Acrylic keeps a
device inventory with names.

**LanFi today.** Security Watch covers evil twins, downgrades, randomized BSSIDs
and deauth bursts from captures. A *new* BSSID that is not an evil twin is
silent, even though it may be a neighbour's new router or an unauthorized AP.

**Why it matters.** It is a one-line extension of a feature LanFi already owns,
and it turns the security screen into something that notices change rather than
only badness.

**What ships.** A persisted baseline set of BSSIDs (first run seeds it), a
`MonitorEventKind.newAccessPoint` event with a toggle and cooldown, and a
Security Watch card listing "new since baseline" with vendor, channel, signal
and first-seen time.

**Acceptance.** A seeded baseline plus a scan containing one new BSSID produces
exactly one event and one notification; restarting the app does not re-announce
the same BSSID.

**Delivered 2026-11-26.** `NetworkBaselineService` seeds on the first scan
silently, then stores unseen BSSIDs in a persisted `pending` list and posts one
aggregated `MonitorEventKind.newAccessPoint` event per scan — one banner per
scan instead of one per BSSID, because the alert policy allows one per kind per
cooldown. Security Watch gained a “New since baseline” card with known/pending
counts, up to six entries with Show, Accept all as known and Reset baseline.
The alert has its own toggle in Monitor alerts; the baseline lives in
`network-baseline.json`. Covered by `Tests/NetworkBaselineTests` (seed, one-time
report, accept, reset, relaunch, dedupe, hidden SSID).

Limitation: the baseline is not per-location, so a laptop that moves between
sites will report the other site's APs until Reset; the card says so. The banner
itself was not observed in a GUI session here.

### G7 — Airtime attribution and legacy-rate detection (P1, M)

**Evidence.** inSSIDer and the MetaGeek App break channel utilization down into
"my network vs. neighbours", rank BSSIDs and clients by airtime, and flag
`Legacy Present` (an 802.11b device on the channel). Chanalyzer adds non-Wi-Fi
duty cycle from a spectrum adapter.

**LanFi today.** `ClientAnalytics` computes per-client airtime and retries from a
capture; `NetworkModel.beaconAirtime` covers beacon overhead; the live scan
shows reported channel utilization. There is no per-BSSID airtime share from a
capture and no legacy-rate detector at all.

**Why it matters.** "Utilization is 70%" is not actionable; "68% of it is the
neighbour's BSSID, and one 802.11b printer drags the channel to 1 Mbps basic
rates" is. The capture pass already parses every frame, so the data is on hand.

**What ships.** (a) Per-BSSID transmitted airtime and frame counts aggregated in
`PcapAnalyzer`, exposed as a "Channel airtime" table sorted by share; (b) a
legacy detector: a BSSID advertising only 1/2/5.5/11 Mbps basic rates, or a
directed data frame at a 1–11 Mbps rate, flagged in the scan table, the
inspector and the survey report; (c) the two feed one insight in Client
Analytics.

**Acceptance.** A fixture capture with two BSSIDs attributes airtime shares that
sum to 100% (± rounding); a beacon with only 802.11b basic rates raises the
legacy flag, and a mixed-mode beacon does not.

**Delivered 2026-11-26.** `PcapAnalyzer.channelAirtime` attributes every frame to
its transmitting BSSID using Duration/ID and ranks the result; the radiotap Rate
field (now parsed, 500 kbit/s units) marks directed data frames at 1–11 Mbit/s.
`ChannelAirtimeEntry` carries frames, airtime, data frames, legacy frames and a
share; `LegacyWiFiDetector` flags a network whose basic rates are all 802.11b.
Client Analytics gained a Channel airtime table with a legacy marker plus two
insights (busiest BSSID share, legacy frames), the scan table gained a “Legacy
802.11b” column with a sort comparator, and the inspector shows the flag in
Technical Specs. Covered by `Tests/ChannelAirtimeTests`.

Not delivered: the survey report has no per-network model to flag (samples
store SSID/BSSID only), and airtime here is the reserved Duration/ID sum, not
measured time-on-air — it is an estimate that ranks BSSIDs correctly, not a
replacement for a spectrum analyzer.

### G8 — Client inventory and RSSI locator (P1, M)

**Evidence.** Acrylic shows clients with a "radar" view for locating a device;
MetaGeek App lists associated and unassociated clients with capabilities and
follows a client across channels; WiFi Lens 1.6 ships AP Radar with an optional
audio pulse that follows RSSI.

**LanFi today.** Captured clients are listed with retries and airtime, and the
Roaming Test tracks the Mac's own transitions. There is no per-client capability
view and no way to walk toward a device.

**Why it matters.** "Which client is that, and where is it?" is a daily
question in offices, and LanFi is one screen away from it.

**What ships.** (a) A client detail sheet from the capture: PHY capabilities from
the association/beacon IEs, first/last seen, frames, retries, airtime, BSSID;
(b) a locator mode that samples one BSSID or client at 4 Hz and shows a large
RSSI readout with an optional ping tone, explicitly labelled "signal guidance,
not direction finding" (WiFi Lens makes the same disclaimer).

**Acceptance.** The locator's sampler is unit-tested for smoothing and for the
signal-lost state; the client sheet renders from a fixture capture. The audio
and the walk are GUI checks and stay unverified in CI.

**Delivered 2026-11-26.** `ClientCapabilitySummary` (in `LanFiCore`) decodes
the association/reassociation request body — supported rates, HT/VHT presence and
stream counts, HE/EHT extension elements, 802.11r and RSN MFPC — and falls back
to the AP beacon, labelled as a fallback, when the capture has no association
frames. `PcapAnalyzer` attaches the summary and first/last-seen timestamps to
`CapturedClient`; Client Analytics opens `ClientDetailView` from a row or its
info button. `SignalLocator` (also `LanFiCore`) is an EMA plus a windowed
least-squares trend and a signal-lost timer; the sheet feeds it from CoreWLAN
scans of the client's BSSID at up to 4 Hz (a scan decides the real cadence),
draws a sparkline, and offers an optional “Tink” ping when the smoothed value
rises by 3 dBm. Covered by `LanFiCoreTests.ClientSignalCoreTests` and
`Tests/ClientCapabilityCaptureTests`; the walk, the audio and the on-screen card
are GUI checks and remain unverified. The locator follows the AP, not the
client's own transmitter, because macOS only exposes per-client RSSI during a
privileged monitor capture — the sheet says so instead of implying direction
finding.

### G9 — Survey visualisations and pass/fail validation (P1, M)

**Evidence.** NetSpot ships 20+ visualisations (SNR, signal, noise, SIR, AP
count, band coverage, interference, throughput, latency, issues); NetAlly
AutoTest applies profiles and produces pass/fail; Sidos and iBwave validate
against user-defined requirements; Ekahau and Hamina produce compliance reports.

**LanFi today.** Survey points carry RSSI, SNR, noise, download and latency, and
the heatmap/report render a subset. There is no requirement profile, so a report
describes but never judges.

**Why it matters.** A handover document that says "coverage is 78%" invites an
argument; one that says "12 of 340 sampled cells fail the −67 dBm / 25 dB SNR
requirement, all on the east stairwell" ends it. This is also the cheapest way
to look more professional than the paid tools on the one artefact the customer
keeps.

**What ships.** `SurveyRequirement` (min RSSI, min SNR, max noise, min
throughput, max latency, per band), a pass/fail overlay on the measured heatmap
and a per-floor summary (pass %, failing cells, worst area), the same verdicts
in the HTML/PDF report, and a default profile that is off until chosen.

**Acceptance.** Two synthetic sample sets, one above and one below the
thresholds, produce the expected pass percentage and failing-cell list; the
report contains the verdict and the requirement values; no requirement is
invented when the user has not set one.

**Delivered 2026-11-26.** `SurveyRequirement` (min RSSI, optional min download,
optional max latency) is stored in `SurveyProject` so it travels with the floor
and saves with the survey; it decodes as off for older files and is off until
the user enables it. `SurveyValidator` returns a pure report: pass percentage,
failing points with their reasons, the unmeasured count, and the worst 3×3 area
("south-east area"). The survey plan rings failing points in red, the inspector
has a Pass/fail card with the thresholds and the verdict, and both the PDF page
and the combined HTML report print the requirement and the verdict. Covered by
`Tests/SurveyValidationTests`.

Not delivered: per-band thresholds (a survey point stores no band) and
noise/SNR criteria (they are not recorded per point, so judging them would mean
inventing numbers). The extra NetSpot-style layers (SIR, AP count, interference)
remain open; this slice delivered the verdict, not 20 visualisations. The card
and the red rings were not viewed in a GUI session here.

### G10 — Reliability score and problem history (P2, S/M)

**Evidence.** WiFi Lens Pro rates a network's reliability over a chosen period
from recorded evidence and lists detected problems with the time they occurred,
including "insufficient observation" periods.

**LanFi today.** The monitor stores samples and events with statistics and a
comparison; the user still has to read a timeline to answer "was last week bad?".

**What ships.** A pure `ReliabilityAssessment` over stored monitor data: scoring
by disconnects, roams, weak-signal time, retry/airtime warnings and coverage
gaps, with explicit "not enough data" below a sample threshold, plus a
problem list with time ranges. Surfaced as a Monitor card and in the report.

**Acceptance.** Fixtures for a clean day, a flapping day and a sparse day
produce high / low / insufficient verdicts; the score is deterministic.

### G11 — Spectrum recording and replay (P2, S/M)

**Evidence.** WiFi Lens Pro records spectrum changes for a selected AP and
replays them; Chanalyzer keeps waterfall history; WiFi Explorer overlays RF and
Wi-Fi data in one window.

**LanFi today.** RF Explorer sweeps are live, Chanalyzer CSV is imported, remote
sweeps are fetched once. Nothing is recorded over time.

**What ships.** A bounded sweep recording (frequency/dBm frames with timestamps)
written next to the capture folder, a scrubber to replay it against the Wi-Fi
table, and export to the existing CSV format. Same privacy rule as captures:
local file only.

**Acceptance.** A recorded 60 s sweep replays at the recorded cadence and the
waterfall matches the source frames; a truncated recording is rejected with a
message.

### G12 — Observation while the app is closed (P2, blocked)

WiFi Lens Pro optionally keeps observing after the app quits. On macOS that
needs a `LaunchAgent` or a `SMAppService` agent plus the same capture/scan
permissions, which is the helper problem already recorded as blocked (P4.1).
Not scheduled; the menu-bar app must stay running, and the UI should say so
plainly rather than implying background collection.

### G13 — Design depth: optimiser, capacity, BOM, roaming simulation (P2, L)

**Evidence.** Ekahau AI Pro auto-places APs and runs a channel planner; iBwave
models capacity, cable and a bill of materials from a 40k-part library; Hamina
simulates client roaming on the plan and commissions APs from inventory.

**LanFi today.** Predictive AP placement, wall materials, antenna patterns,
multi-floor, cutouts and calibration from samples. No optimiser, no capacity or
throughput demand model, no BOM, no roaming simulation.

**Why it is P2.** Each of these is a product of its own, and the current
predictor is honest precisely because it does not pretend to model capacity. The
narrow slice worth taking later is **roaming simulation on the plan** (reusing
`RoamProbeAnalyzer`'s rules against predicted RSSI) and a **capacity estimate**
(clients × demand vs. airtime per AP), both clearly labelled as estimates.

### G14 — 3D model and CAD import (not scheduled)

Hamina, iBwave, Ekahau and Sidos build 3D models, often with AI wall detection
from a floor plan. LanFi accepts a raster floor plan, draws walls by hand and
models floors with a fixed inter-floor loss. A DWG/DXF/IFC pipeline plus a
3D propagation engine is a different product; the first plan already scoped the
3D view to visualisation, and that is where it stays.

### G15 — Discovery depth: VLAN, switch port path, authorization (P1, M)

**Evidence.** NetAlly EtherScope nXG discovers devices across VLANs and SSIDs,
correlates wired and wireless results, shows the switch/router path to a device,
detects duplicate IPs and congested ports, and supports batch authorization and
discovery-difference audits, enriched from SNMP MIBs.

**LanFi today.** LAN Scanner does ARP/ICMP/TCP, Bonjour/SSDP names, OUI vendors,
open ports and Network Guard; `RouterPollingService` performs one SNMP v2c GET of
standard interface counters. No bridge/port mapping, no VLAN, no device-type
classification, no baseline diff of the device list.

**Why it matters.** "Who is on my network and where is it plugged in?" is the
question that makes an analyzer useful to IT rather than to a Wi-Fi hobbyist,
and LanFi already has the SNMP subset, the ARP table and the Bonjour parser.

**What ships.** (a) SNMP `BRIDGE-MIB` dot1dTpFdbTable / Q-BRIDGE walk to map a
MAC to a bridge port and, where `LLDP-MIB` answers, to the neighbouring switch;
(b) VLAN IDs from the same walk; (c) a device baseline with "new device since"
and an authorization flag, feeding the existing notification rules; (d) a
device-type label from Bonjour service type, OUI and open ports, marked as
inferred.

**Acceptance.** Recorded SNMP responses map a MAC to a port and VLAN; the
baseline diff reports one new and one missing device; the classifier's labels
are stable and marked inferred in the UI.

**Delivered 2026-11-27.** `BridgeMIB` (in `LanFiCore`) decodes a recorded
BRIDGE-MIB/Q-BRIDGE walk into MAC → bridge port → ifIndex/ifDescr → VLAN, using
`dot1dTpFdbPort`, `dot1qTpFdbPort` and `dot1qVlanFdbId`; a VLAN row replaces the
plain row for the same MAC, and a missing VLAN table leaves the VLAN nil instead
of assuming VLAN 1. `LLDP` decodes `lldpRemTable` into one neighbour per local
port. `SNMPClient` gained a bounded GETNEXT walk (`SNMPBER.getNextRequest`,
ordered variable bindings, `endOfMibView`, a row cap, and a mid-table timeout
that returns the rows already received), and the LAN scanner's inspector opens a
**Switch port lookup** sheet that reads those tables and shows the selected
MAC's port, VLAN and uplink. `DeviceRoleClassifier` labels a device from its
advertised role, services, open ports and vendor/hostname, and the inspector
marks a derived kind as inferred. `DeviceInventoryEvaluator` keeps first/last
seen and an authorization flag per device; the scan card reports untrusted and
missing counts, seeds silently on the first guarded scan, and the old key-only
`lan-guard.json` is migrated to trusted entries.

Not delivered: LLDP is only used to name the far end of a port (no
`lldpRemPortId`/chassis-id decoding), a device behind a downstream switch still
reports that switch's port rather than the edge port, and SNMPv3 is not
implemented. No real switch was queried here — the decoders and the walk wire
format are covered by `LanFiCoreTests.BridgeMIBTests`,
`LanFiCoreTests.DeviceInventoryTests` and `Tests/SwitchInventoryTests`; the
sheet, its table and the trust actions were not opened in a GUI session.

### G16 — Menu-bar display template (P2, S)

WiFi Signal exposes 18 metrics through a display-pattern string (`%N | Ch %C@%W
MHz`). LanFi's menu-bar label offers five metric choices in fixed formats. A
small template engine over the existing sampler would close this, but it is
polish, not a workflow gap; take it only if the menu bar becomes a focus again.

## What this does not change

- **The first plan's open items stay open.** Signing, the helper, the MAS split,
  live Wi-Spy, the Zigbee adapter and the hands-on VoiceOver pass are unchanged
  and still blocked for the same external reasons.
- **Widgets and `LanFiCore` are still worth doing** (P1.6 and the modularity
  item). Neither appears above because no competitor's feature depends on them;
  they are engineering bets, not parity gaps.
- **Privacy stays a differentiator.** Cloud upload (Airtool), cloud reporting
  (Link-Live, Hamina) and cloud design (Ekahau Online) are all non-goals. LanFi's
  self-contained HTML/PDF report is the local answer, and G9 makes it stronger.
- **MCP is already ahead.** 7SIGNAL and WiFi Lens both advertise agent access;
  LanFi shipped live MCP actions in 5.6.x, so there is no gap to close here.

## Recommended next slice

The three items that remove the most "open another app" moments for the least
risk, in order:

1. ~~**G1 + G2 — capture ergonomics.**~~ Delivered 2026-11-26.
2. ~~**G5 + G6 — snapshots and environment baseline.**~~ Delivered 2026-11-26.
3. ~~**G9 — pass/fail survey requirements.**~~ Delivered 2026-11-26, together
   with G4b (import aliases and the unmapped-column report).

G4 (field catalogue) and G7 (airtime attribution, legacy flag) shipped on
2026-11-26 with G4b, G8 (client detail and signal locator) followed, and G15
(SNMP bridge/VLAN path and an authorized device inventory) shipped on
2026-11-27. The next slice is G10: a reliability score over stored monitor data,
which needs no hardware and reuses the samples the monitor already keeps.

## Sources

Read 2026-11-26.

- WiFi Explorer Pro 3 — <https://www.intuitibits.com/products/wifiexplorerpro3>,
  <https://docs.intuitibits.com/wifiexplorerpro3/about>,
  release notes <https://www.intuitibits.com/release-notes/wifiexplorerpro3/>
  (3.10 added PCAPNG export and restored passive scan on M5 Macs).
- Airtool 2 — <https://www.intuitibits.com/products/airtool2>,
  <https://docs.intuitibits.com/airtool2/about>,
  <https://docs.intuitibits.com/airtool2/advanced-settings> (slicing, dwell,
  5/6 GHz bands, PSC-only), <https://docs.intuitibits.com/airtool2/capture-using-a-sensor>.
- NetSpot 6 — <https://www.netspotapp.com/netspot-mac.html>,
  <https://www.netspotapp.com/help/netspot-wifi-heatmaps>,
  <https://www.netspotapp.com/help/netspot-6-0-with-multi-floor-planning/>.
- inSSIDer 5 / MetaGeek App — <https://support.oscium.com/hc/en-us/articles/360042833434-inSSIDer-5-for-Mac-Beta-User-Guide>,
  <https://support.metageek.com/hc/en-us/articles/16676518627735-MetaGeek-App-User-Guide>,
  <https://www.oscium.com/products/metageek-app>.
- Acrylic Wi-Fi — <https://www.acrylicwifi.com/en/wifi-analyzer>,
  <https://www.acrylicwifi.com/en/wifi-sniffer>.
- NetAlly AirCheck G3 Pro / EtherScope nXG / Link-Live —
  <https://www.netally.com/products/aircheckg3/>, <https://www.netally.com/products/etherscopenxg/>,
  <https://www.netally.com/products/link-live>.
- Ekahau AI Pro — <https://www.ekahau.com/products/ai-pro/>,
  <https://support.ekahau.com/hc/en-us/articles/41570999890833-Ekahau-AI-Pro-Overview>.
- Hamina — <https://hamina.com/product>, <https://www.hamina.com/>.
- iBwave Design — <https://www.ibwave.com/products/ibwave-design/>.
- Sidos — <https://www.sidos.com/sidos-deep-survey>, <https://www.sidos.com/>.
- eino Site Survey — <https://www.eino.ai/blog-posts/eino-launches-site-survey>.
- 7SIGNAL MCP — <https://www.7signal.com/blog/mcp-wi-fi-monitoring-use-your-network-data-inside-any-ai-tool>.
- WiFi Signal — <https://www.intuitibits.com/products/wifisignal>,
  <https://docs.intuitibits.com/wifisignal/about>.
- WiFi Lens — <https://wifi-lens.shiinalabs.com/download>,
  <https://github.com/ShiinaLabs/wifi-lens>, release v1.6.0.
