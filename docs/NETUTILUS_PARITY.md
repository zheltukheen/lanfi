# Netutilus parity analysis

_Researched 2026-11-10 against [netutilus.com](https://netutilus.com/) (Netutilus
1.20.2, 16 Oct 2026) and the shipped source in this repository._

Netutilus is a commercial, sandboxed, Mac App Store **general network toolkit**
(20 tools in five groups, 13 free + a one-time Pro unlock). LanFi started as a
free, source-available **Wi-Fi analyzer**; the toolkit expansion added most of
the adjacent tooling as first-class screens. The overlap is no longer narrow —
what differs is the probe layer and the distribution model.

Full parity is therefore a **product-scope decision**, not a missing screen. This
document separates what is genuinely missing from what is delivered but still
depends on an external binary.

> **Status 2026-11-22 — long-term target, not a release checklist.** The toolkit
> expansion shipped most of the catalogue as first-class screens, so the
> original gap matrix below is history, not the current state. Parity is still
> deliberately incomplete: the throughput test wraps Apple's `networkQuality`,
> traceroute/MTR wrap `traceroute`, the LAN scanner reads ARP/route through
> `Process` (the diagnostics gateway check still shells `ping`), and the app is
> not notarized or sandboxed. The acceptance section marks each criterion as
> met, partial or parked, with the code that decides it.

## Positioning

| | Netutilus | LanFi |
| --- | --- | --- |
| Category | General network toolkit | Wi-Fi analyzer + network toolkit |
| Tools | 20 across diagnostics, DNS/domains, network, monitoring | Wi-Fi analysis, diagnostics, survey, capture, 20+ toolkit screens |
| Price | Free + one-time Pro | Free, FSL-1.1-ALv2 |
| Distribution | Mac App Store, sandboxed, notarized | DMG/ZIP + Homebrew; ad-hoc or Developer ID signing, no notarization or sandbox yet |
| Networking | Network.framework, CoreWLAN, native ICMP, no shell-out | CoreWLAN, URLSession, native ICMP/DNS/TLS/TCP probes; `Process` for `networkQuality`, `traceroute`/MTR, `tcpdump`, `arp`/`route` |
| Platform | macOS 14.6+ | macOS 13+ |
| Languages | English | 5 languages |

The important architectural difference is the **Networking** row: Netutilus
explicitly **never shells out**. LanFi's ping tool, DNS client, TLS inspector and
port/path probes are native already; what still shells out is the throughput
test, traceroute/MTR, packet capture and the ARP/route reads behind the LAN
scanner. That residue is the main reason the last step to parity is not a
UI-only project.

## Coverage matrix

> **Re-audited 2026-11-22.** The matrix below describes the code as it ships,
> not the 2026-11-10 gap. What still depends on an external binary is marked
> Partial; nothing in the catalogue is absent any more. See
> [`TOOLKIT_SCREENSHOT_GAP.md`](TOOLKIT_SCREENSHOT_GAP.md) for screenshots.

Status legend: **Ahead** — LanFi has more than Netutilus; **Parity** — comparable;
**Partial** — some real implementation, missing the product surface; **Wrapper** —
only an external command, no parsed result; **Absent** — nothing shipped.

| # | Netutilus tool | Tier | LanFi today | Status |
| --- | --- | --- | --- | --- |
| 1 | Internet Check | free | `DiagnosticsEngine` runs Wi-Fi link, IPv4/IPv6, gateway ICMP, DNS, captive portal, latency, with per-check pass/warn/fail and a one-line verdict with evidence | **Parity** |
| 2 | Ping | free | Native unprivileged ICMP (`ICMPPingProbe`), live chart, jitter/loss, up to 10k probes; the diagnostics gateway check still uses `/sbin/ping` | **Ahead** |
| 3 | Traceroute | free | Parsed hop table, per-hop latency, copy/export; runs `traceroute` and parses it | **Partial** |
| 4 | MTR | pro | `MTRService` runs repeated traceroute rounds and aggregates per-hop loss/jitter | **Partial** |
| 5 | Visual Traceroute | pro | MapKit route with hop list and inspector | **Parity** |
| 6 | Speed Test | free | `/usr/bin/networkQuality` parsed into down/up/latency, bufferbloat grade, history and schedule | **Partial** |
| 7 | DNS Lookup | free | Native UDP, DoH and DoT clients with record types and resolver choice | **Parity** |
| 8 | DNS Propagation | free | Same query across public resolvers, compared side by side | **Parity** |
| 9 | Whois | free | RDAP lookup; no `whois` shell | **Parity** |
| 10 | GeoIP | free | Opt-in `ipwho.is` lookup, documented in `PRIVACY.md` | **Parity** |
| 11 | SSL Certificate | free | `Security.framework` chain: issuer, validity, days left | **Parity** |
| 12 | Port Scan | free | Native `NWConnection` connect scan with service map and cancellation | **Parity** |
| 13 | Path Check | free | Arbitrary `host:port` over TCP/HTTPS | **Parity** |
| 14 | Subnet Calculator | free | CIDR math and UI | **Ahead** |
| 15 | iperf3 | pro | Client screen and parsed output; runs the user-installed `iperf3` binary | **Partial** |
| 16 | Network Monitor | free | `InterfacesView` + `SystemInterfaceScanner`: addresses, gateway, DNS, VPN interfaces, RX/TX counters | **Parity** |
| 17 | Uptime Monitor | pro | Scheduled HTTP/TCP checks, notifications, outage history and menu-bar status | **Parity** |
| 18 | LAN Scanner + Network Guard | pro | ARP + Bonjour + TCP sweep: IP/MAC/vendor/latency/ports, new-device alerts; no monitor mode needed, but ARP/route are read through `Process` | **Partial** |
| 19 | Wi-Fi Analyzer | pro | Quality score, RSSI/noise/SNR, security audit, diagnostics | **Ahead** |
| 20 | Wi-Fi Networks | pro | Scan, IE decode, 6 GHz/Wi-Fi 7, ranked channel advice, survey | **Ahead** |

Summary: **4 ahead, 11 at parity, 5 partial, 0 absent.**

Two caveats on this matrix:

- "Parity" means the tool is first-class; it does not mean identical probe
  internals. Traceroute, MTR, speed test and iperf3 remain partial because they
  still depend on an external binary, which is exactly the gap section 1 below
  describes.
- Internet Check now has the one-line verdict with evidence (`DiagnosticsVerdict`
  and its verdict card), which was the missing product surface in the original
  analysis.

## Cross-cutting gaps

These block parity regardless of how many tool screens are added.

### 1. Native probe layer instead of `Process`

Current shell-outs (audited 2026-11-22): `/usr/bin/networkQuality` (speed test),
`traceroute` (traceroute and the MTR rounds), `/usr/sbin/tcpdump` (capture),
`/usr/sbin/arp` and `/sbin/route` (LAN scanner), `/sbin/ping` in the diagnostics
transport (the Ping tool itself is native), plus optional `iperf3`/`ssh`/`nmap`.
Text parsing is locale- and macOS-version-fragile, and none of it can ship in a
sandbox. Already native, behind injectable protocols and covered without network
access: unprivileged ICMP ping (`ICMPPingProbe`), the UDP/DoH/DoT DNS clients,
the `Security.framework` TLS inspector and the `NWConnection` port/path probes.
Netutilus's claim — "sandboxed, never shells out, results are the app's own" —
still requires replacing the rest with:

- ICMP echo over an unprivileged datagram ICMP socket, streaming per-probe results;
- TCP connect probes over `NWConnection` (ping and path check);
- DNS record queries (`DNSServiceQueryRecord` or Network.framework) for A/AAAA/MX/
  TXT/NS/SOA/CNAME/SRV/CAA, with a selectable resolver;
- TLS chain inspection with `Security.framework` (issuer, validity, days left);
- a TTL-stepping traceroute/MTR engine with per-hop loss and jitter;
- a bounded-concurrency TCP port prober with a service-name map.

This layer is the prerequisite for the remaining partial tools. Build it once,
behind injectable protocols, with tests that never touch the network — the same
pattern as `DiagnosticsTransport` and `PingProbing`, which already exist. The
throughput test is the one item with no public native API: `networkQuality` is
Apple's own measurement service, so replacing it means either accepting the
shell-out or writing a saturating transfer test that will not match Apple's
numbers.

### 2. Distribution and sandbox

There is no entitlements file; builds are ad-hoc signed. The Mac App Store
requires App Sandbox, which breaks `tcpdump`, SSH remote sensors and USB-serial
spectrum. Netutilus has none of those. The realistic choice is:

- **Developer ID + notarization** (already on the roadmap) and keep the
  privileged/pro features; or
- **split**: sandboxed MAS build for the toolkit, Developer ID build for
  capture/SSH/hardware.

This decision gates the "parity" claim because Netutilus's distribution is part
of its product.

### 3. Persistence and notifications

This is no longer a gap: `UptimeMonitor` keeps a timestamped outage history and
posts through `MonitorNotifier`, scheduled speed tests persist their runs, and
`MenuBarExtra` shows the status. What remains is scale — the history is bounded
and in memory/JSON, not a queryable metrics store — and that is a product
decision rather than a parity blocker.

### 4. Third-party data sources and privacy

Whois/RDAP, DNS propagation, GeoIP and visual traceroute use external services
(`rdap.org`, six public DNS resolvers, `ipwho.is`). They run only when the user
presses the corresponding action, and `PRIVACY.md` now documents each request.

### 5. Localization and accessibility

This is shipped: the toolkit expansion added its strings to all five locales and
put accessibility labels on icon-only controls, charts and cards. The cost turned
out to be real — it has to be paid per screen, not swept up at the end — which is
why D7 in the gap analysis still wants a hands-on VoiceOver run.

## Roadmap to parity

Estimates are order-of-magnitude person-days for one experienced macOS developer,
including tests and localization but excluding review time. They are the
2026-11-10 estimate and are kept for scale: much of Phase 1 and 2 landed during
the toolkit expansion, and Phase 0 is partly done (ping, DNS, TLS, port/path), so
the remaining work is smaller and narrower than the table suggests.

### Phase 0 — Native probe layer (prerequisite)

ICMP + TCP + DNS records + TLS chain + traceroute/MTR + port prober, all behind
injectable transports, no `Process` for ping or speed test.

**Exit:** a pure-Swift `NetProbe` module with unit tests; `DiagnosticsEngine` and
the new tools consume it; no shell parsing on the hot path.
**Status 2026-11-22:** partly met. `PingProbing`/`ICMPPingProbe`, the DNS clients,
`TLSCertificateInspector`, `PortScanner` and the path probe are native and
tested; traceroute/MTR, the diagnostics gateway ping, the LAN ARP/route reads and
`networkQuality` are not.
**Effort:** the remaining native work is 4–6 days; the original 10–15 assumed
nothing had shipped.

### Phase 1 — Free-tool parity

| Item | Work | Days |
| --- | --- | --- |
| Internet Check verdict | Attribute failures to Wi-Fi / router / provider from link, gateway, DNS, HTTP and hop evidence; one plain-language result | 2–3 |
| Ping | ICMP + TCP, configurable up to 10k probes, live chart, jitter/loss summary | 3–4 |
| Traceroute | Parsed hop table, latency per hop, copy/export | 2 |
| MTR | Continuous per-hop loss/jitter, start/stop | 3 |
| DNS Lookup | All common record types, resolver choice, TTL, raw response | 2–3 |
| Path Check | Arbitrary `host:port`, TCP reachability, route hint | 1 |
| Port Scan | TCP connect scan, service map, concurrency limits, cancellation | 4–5 |
| SSL Certificate | Chain, issuer, validity, days left, expiry warning | 2 |
| Subnet Calculator | Pure CIDR math + UI | 0.5 |
| Speed Test | Bufferbloat grade, history, per-run comparison | 2–3 |

**Exit:** all 13 free tools have first-class UI, parsed results and copy/export.
**Status 2026-11-22:** shipped except the native-probe part; traceroute, MTR and
speed test have screens but still call external binaries. The remaining work is
the Phase 0 residue, not new screens.
**Effort:** 20–26 days originally; ~5 days left, all in native probes.

### Phase 2 — Monitoring and LAN (Pro-adjacent)

Uptime Monitor (HTTP/TCP checks, interval, notifications, outage history, menu-bar
status), scheduled speed tests, native LAN scanner (ARP table + mDNS/Bonjour +
TCP probe, IP/MAC/vendor/latency, optional ports), Network Guard new-device alerts.
**Status 2026-11-22:** shipped. The LAN scanner still reads ARP and the default
route through `Process`.
**Effort:** 14–19 days originally.

### Phase 3 — Data and map

Whois/RDAP, DNS propagation across public resolvers, GeoIP (bundled DB or opt-in
API), visual traceroute with MapKit.
**Status 2026-11-22:** shipped (RDAP for whois, `ipwho.is` opt-in for GeoIP).
**Effort:** 9–12 days originally.

### Phase 4 — Distribution

Notarization and/or the sandboxed MAS split, privacy manifest, permissions copy.
**Effort:** 8–12 days plus an Apple Developer Program account.

**Full parity: the original estimate was 61–84 person-days; what is left is the
native probe residue (4–6 days) plus the distribution decision (8–12 days).**

## Recommended scope

Cloning all 20 tools would make LanFi a weaker Netutilus; Netutilus's moat is
breadth, LanFi's is Wi-Fi depth. The defensible subset is the troubleshooting
chain that starts from "my Wi-Fi is bad":

1. **Internet Check verdict** — connects LanFi's RF evidence to provider
   attribution. Neither Netutilus nor WiFi Explorer has LanFi's radio data, so
   this is the one place where parity becomes differentiation.
2. **Ping + Traceroute + MTR**, native and charted — Ping is native and charted
   already; traceroute/MTR are next.
3. **DNS Lookup + Path Check + Port Scan + SSL** — native since the toolkit
   expansion.
4. **Uptime Monitor** with menu-bar status — shipped.

**Superseded:** Whois, GeoIP, DNS Propagation, Visual Traceroute, LAN
Scanner/Guard, Uptime Monitor and scheduled speed tests have since shipped as
part of the toolkit expansion.

The recommended subset is delivered apart from the native traceroute/MTR engine
and the distribution decision; the rest of this document explains what full
parity would still cost.

## Acceptance criteria for "Netutilus parity"

This is the **long-term target** that would justify the word "parity", not a
release checklist. It is deliberately hard: three of these items are product
decisions with real trade-offs, not pending tickets. State as of 2026-11-22:

- [~] **No `Process` or shell-out for the probe paths, every probe
      sandbox-viable.** Native and already injectable: the Ping tool
      (unprivileged `SOCK_DGRAM` ICMP), DNS lookup/propagation (UDP/DoH/DoT),
      TLS inspection (`Security.framework`), port scan and path check
      (`NWConnection`). Still shell-based: speed test (`networkQuality`),
      traceroute and MTR rounds, the diagnostics gateway ping, LAN-scanner ARP
      and route reads, packet capture. Closing the traceroute/MTR and gateway
      parts means a TTL-stepping ICMP engine; closing the speed-test part has no
      native equivalent, because `networkQuality` **is** Apple's measurement
      service.
- [~] **13 free tools have first-class UI, parsed results, copy and export.**
      All 14 free tools have a screen and parsed output; copy is present on
      every result surface, export on the ones where a file is meaningful
      (history, capture, survey, diagnostics). Per-screen export is not a
      uniform contract, so this stays partial.
- [x] **Internet Check returns a Wi-Fi/router/provider verdict with evidence.**
      `DiagnosticsVerdict` turns the checks into one plain-language result and
      exposes the checks that support it.
- [x] **Uptime Monitor runs scheduled checks, notifies, and keeps outage
      history.** `UptimeMonitor` schedules HTTP/TCP checks, `MonitorNotifier`
      posts notifications with authorization, and the outage list is kept.
- [x] **Speed Test shows a bufferbloat grade and history.** `ThroughputReport`
      derives the grade from `networkQuality` responsiveness and groups the runs;
      the probe itself remains the shell-out noted above.
- [x] **LAN Scanner lists IP/MAC/vendor/latency/ports without monitor mode.**
      `LANScannerService` reads the ARP table, browses Bonjour and probes TCP;
      the ARP/route reads are the shell residue, not a monitor-mode requirement.
- [x] **All new strings localized in the five shipped languages, with VoiceOver
      labels.** `Resources/{en,ru,de,fr,zh-Hans}.lproj` carry the toolkit
      strings, and icon-only controls, charts and cards expose accessibility
      labels; the hands-on VoiceOver audit is tracked as D7 in
      [`GAP_ANALYSIS_2026-11.md`](GAP_ANALYSIS_2026-11.md), not here.
- [ ] **Distribution is notarized and/or sandboxed for the Mac App Store.**
      Parked as a product decision: there is no entitlements file, `build.sh`
      signs ad-hoc unless `CODESIGN_IDENTITY` is set, and the sandbox would
      remove capture, SSH sensors and USB-serial spectrum. It needs an Apple
      Developer Program account and a split Developer ID / MAS build — see
      [`DISTRIBUTION.md`](DISTRIBUTION.md).

None of the open items blocks the shipped product: they block the claim of
"Netutilus parity", which remains a scope choice rather than a backlog.
