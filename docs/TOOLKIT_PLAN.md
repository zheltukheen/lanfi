# Network toolkit implementation plan

_Companion to [`NETUTILUS_PARITY.md`](NETUTILUS_PARITY.md). This is the build
plan; the parity document is the gap analysis._

## Design reference

Local screenshots of Netutilus 1.20.2 are in `build/reference/netutilus/`
(git-ignored, downloaded from the public site): Internet Check, LAN Scanner,
Port Scan, DNS Lookup, Uptime Monitor, Visual Traceroute, Wi-Fi Networks.

What to borrow:

- **Source-list sidebar**, grouped by job: Diagnostics, DNS & Domains, Network
  Tools, Monitoring. Icon + label, strong blue selection, Pro badge where paid.
- **Detail pane toolbar**: run, save/report, export, clear, info on the right;
  a status pill ("Scan complete · open ports: 8", "10 devices found") sits at
  the top-right of the content, not in the toolbar.
- **One verdict card first**: big status, plain-language sentence, evidence
  chips and a left-to-right path diagram (This Mac → Router → Internet → DNS →
  Web). Details come after it.
- **Tables** with a leading status dot, colored type badges, monospaced values
  and right-aligned latency; hover row, blue selected row; a right inspector
  with summary counts and a "what is open" list.
- **Cards** on `controlBackgroundColor`, radius 8, uppercase caption section
  labels; generous 12–16 pt spacing.
- **Empty states** with a short explanation, never a blank pane.

LanFi keeps its own brand (system accent, existing icon set, 5 languages) and
does not copy Netutilus pixel-for-pixel.

## Window and navigation

One new window, not a rebuild of the analyzer window:

- `NetworkToolkitView` — `NavigationSplitView` with the grouped sidebar.
- `ToolboxTool` — one enum for id, title, icon, section, availability.
- Opened from the main toolbar, **Layout → Network Toolkit** and `lanfi://toolkit/<tool>`.
- Wi-Fi Analyzer / Wi-Fi Networks rows open the existing main window instead of
  duplicating the analyzer.
- Network Monitor embeds the existing `InterfacesView`.
- Internet Check embeds the diagnostics engine; Phase 1 adds the verdict.

Files:

```text
Models/ToolboxTool.swift              tool catalogue + sections
Models/ToolkitModels.swift            probe result value types
Models/SubnetCalculator.swift         pure CIDR math
Services/Toolkit/ICMPPingProbe.swift  unprivileged SOCK_DGRAM ICMP
Services/Toolkit/TCPPingProbe.swift   NWConnection connect timing
Services/Toolkit/PingService.swift    resolve + run + summarize
Services/Toolkit/DNSMessage.swift     query builder / response parser
Services/Toolkit/DNSClient.swift      UDP transport + resolvers
Services/Toolkit/PortSpec.swift       "21-23,80,443" parser + presets
Services/Toolkit/PortScanner.swift    bounded-concurrency TCP scan
Services/Toolkit/TLSCertificateInspector.swift
Services/Toolkit/TracerouteRunner.swift + parser
ViewModels/ToolkitViewModel.swift     per-tool state, cancellation
Views/Toolkit/NetworkToolkitView.swift
Views/Toolkit/PingToolView.swift
Views/Toolkit/TracerouteToolView.swift
Views/Toolkit/DNSToolView.swift
Views/Toolkit/PortScanToolView.swift
Views/Toolkit/PathCheckToolView.swift
Views/Toolkit/SSLToolView.swift
Views/Toolkit/SubnetToolView.swift
```

## Phase 0 — native probe layer

Order matters: pure data and parsers first, transports last.

1. **Value types and parsers** (pure, testable headless):
   `SubnetCalculator`, `PortSpec`, `DNSMessage` query/response codec,
   `TracerouteOutputParser`, target validation (`host`, `host:port`, CIDR).
2. **ICMP ping**: unprivileged `SOCK_DGRAM`/`IPPROTO_ICMP`, checksum, sequence,
   `poll` timeout, strip the IPv4 header that macOS returns, match echo replies.
   Verified locally: this works without root. `IP_TTL` is ignored on these
   sockets, so this cannot be used for traceroute.
3. **TCP ping**: `NWConnection` to `host:port`, `.ready` time, timeout and
   refusal mapping.
4. **DNS**: UDP query to a selected resolver, compression-pointer parser,
   A/AAAA/MX/TXT/NS/SOA/CNAME/SRV/CAA/PTR. TCP retry for truncated answers is a
   later increment.
5. **Port scan**: TCP connect probe with a concurrency cap, `.ready` = open,
   refusal = closed, timeout = filtered; service-name map; optional banner grab.
6. **TLS**: `URLSession` challenge to read the server `SecTrust` chain, issuer,
   validity and days remaining; cancel the request once the challenge fires.
7. **Traceroute**: `/usr/sbin/traceroute -n -m 30 -w 2 -q 1` is setuid root on
   macOS, so it runs unprivileged. Parse hops and timing; no shell interpolation.
   A native TTL engine is not possible without a privileged helper — record that
   decision in the parity doc.

Exit criteria: pure codecs/parsers have tests; transports have injected fakes;
`xcodebuild test` stays green; no `Process` for ping or DNS.

## Phase 1 — tool screens

Implement in this order, one commit per tool where practical:

1. **Ping** — host field, ICMP/TCP toggle, count and interval, live samples,
   min/avg/max/stddev/loss, chart, copy/export.
2. **Traceroute** — parsed hop table, per-hop latency, copy/export; MTR later.
3. **DNS Lookup** — type picker, resolver (System/Cloudflare/Google/custom),
   record table with TTL/priority, inspector summary.
4. **Port Scan** — target, port presets/spec, timeout/concurrency, service map,
   status summary, inspector of open ports.
5. **Path Check** — `host:port` TCP reachability plus optional route.
6. **SSL Certificate** — chain, issuer, validity, days remaining, expiry state.
7. **Subnet Calculator** — CIDR input, network/broadcast/range/host count.
8. **Internet Check** — add a `DiagnosticVerdict` to the engine
   (local Wi-Fi / router / provider / DNS / web / healthy) with evidence and the
   path diagram; reuse it in the existing diagnostics tab.
9. **Speed Test** — move the throughput section into its own tool, add a
   bufferbloat grade and a persisted history.

Phase 1 exit: the eight free tools plus Internet Check and Speed Test have
first-class screens; the toolkit replaces the raw external-command console.

## Phase 2 — monitoring and LAN

Uptime Monitor (HTTP/TCP checks, interval, notifications, outage history,
menu-bar status), scheduled speed tests, native LAN scanner (ARP + mDNS +
TCP probe + OUI vendor + latency), Network Guard alerts, iperf3 client.

## Phase 3 — data and map

Whois/RDAP, DNS propagation, GeoIP, visual traceroute.

## Phase 4 — distribution

Notarization and/or sandboxed Mac App Store split; privacy manifest.

## Test strategy

- **Pure**: subnet math, port spec, DNS wire codec, traceroute parsing, verdict
  rules, ping statistics. Golden byte fixtures for DNS.
- **Injected transports**: ping, port probe and TLS inspector take protocols so
  tests never touch the network. No sleeps longer than a few milliseconds.
- **No UI tests** that need Location or network access; test view-model state
  transitions instead.
- Add every new pure file to `LanFiTests` sources in `project.yml`; app files are
  picked up from the directory globs automatically.

## Constraints and decisions

- Public APIs only. ICMP uses the unprivileged datagram socket, not raw sockets.
- Traceroute stays on the setuid system binary until a privileged helper is
  designed; this is the one accepted exception to "no shell", and it is isolated
  behind `TracerouteRunner` so it can be replaced.
- No App Sandbox yet. New probes are written so they remain sandbox-viable.
- All new strings go through the existing localization flow; VoiceOver labels
  on icon-only controls.
- Keep scanning and parsing off the main thread; UI state stays `@MainActor`.


## Delivered in the first tranche

- [x] Phase 0: value types, subnet/port/target parsers, DNS wire codec, ICMP
      and TCP ping, UDP DNS client, TCP port scanner, TLS chain inspector,
      traceroute runner and parser — 49 new headless tests.
- [x] Toolkit window with the grouped custom sidebar and Planned badges.
- [x] Internet Check verdict and path diagram.
- [x] Ping, Traceroute, DNS Lookup, Port Scan, Path Check, SSL Certificate,
      Subnet Calculator and Speed Test screens.
- [x] MTR (repeated traceroute with per-hop loss/jitter).
- [x] Speed-test history and hourly/6h/daily scheduling.
- [x] Uptime Monitor, LAN Scanner and iperf3 client.
- [x] Localisation of the toolkit strings in five languages.
- [ ] Whois, GeoIP, DNS Propagation and Visual Traceroute remain planned.
