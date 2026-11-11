# Netutilus parity analysis

_Researched 2026-11-10 against [netutilus.com](https://netutilus.com/) (Netutilus
1.20.2, 16 Oct 2026) and the shipped source in this repository._

Netutilus is a commercial, sandboxed, Mac App Store **general network toolkit**
(20 tools in five groups, 13 free + a one-time Pro unlock). LanFi is a free,
source-available **Wi-Fi analyzer** with a diagnostics tab. The overlap is real
but narrow: Wi-Fi, a basic internet check, and an interface monitor. Everything
else in Netutilus's catalogue is adjacent tooling LanFi does not have as a
first-class feature.

Full parity is therefore a **product-scope decision**, not a missing screen. This
document separates what is genuinely absent from what only looks absent because
it is a raw command wrapper today.

## Positioning

| | Netutilus | LanFi |
| --- | --- | --- |
| Category | General network toolkit | Wi-Fi analyzer |
| Tools | 20 across diagnostics, DNS/domains, network, monitoring | Wi-Fi analysis, diagnostics, survey, capture |
| Price | Free + one-time Pro | Free, FSL-1.1-ALv2 |
| Distribution | Mac App Store, sandboxed, notarized | DMG/ZIP + Homebrew, ad-hoc signed, notarization pending |
| Networking | Network.framework, CoreWLAN, native ICMP, no shell-out | CoreWLAN, URLSession, `getaddrinfo`, `Process` for `ping`/`networkQuality`/`tcpdump` |
| Platform | macOS 14.6+ | macOS 13+ |
| Languages | English | 5 languages |

The important architectural difference is the **Networking** row: Netutilus
explicitly **never shells out**, while LanFi does for several core paths. That is
the main reason "add the missing tools" is not a UI-only project.

## Coverage matrix

> **Update 2026-11-11:** the toolkit now also ships MTR, Uptime Monitor, LAN
> Scanner with Network Guard, iperf3, speed-test history/scheduling, search and
> recents, DNS Propagation, Whois/RDAP, GeoIP, Visual Traceroute and
> five-language localisation. Remaining: notarization and a sandboxed MAS
> build. The matrix below is the original gap analysis; see
> [`TOOLKIT_SCREENSHOT_GAP.md`](TOOLKIT_SCREENSHOT_GAP.md) for current status.

Status legend: **Ahead** — LanFi has more than Netutilus; **Parity** — comparable;
**Partial** — some real implementation, missing the product surface; **Wrapper** —
only an external command, no parsed result; **Absent** — nothing shipped.

| # | Netutilus tool | Tier | LanFi today | Status |
| --- | --- | --- | --- | --- |
| 1 | Internet Check | free | `DiagnosticsEngine` runs Wi-Fi link, IPv4/IPv6, gateway ICMP, DNS, captive portal, latency, with per-check pass/warn/fail | **Partial** |
| 2 | Ping | free | `/sbin/ping` parsed by `PingOutputParser`; fixed 3–10 probes | **Partial** |
| 3 | Traceroute | free | `traceroute` entry in `ToolCatalog`; raw text only | **Wrapper** |
| 4 | MTR | pro | `mtr` entry in `ToolCatalog`, requires `brew install mtr`; raw text only | **Wrapper** |
| 5 | Visual Traceroute | pro | — | **Absent** |
| 6 | Speed Test | free | `/usr/bin/networkQuality` parsed into down/up/latency/responsiveness | **Partial** |
| 7 | DNS Lookup | free | `getaddrinfo` A/AAAA for one fixed host | **Partial** |
| 8 | DNS Propagation | free | — | **Absent** |
| 9 | Whois | free | — | **Absent** |
| 10 | GeoIP | free | — (the OUI DB maps MAC prefixes, not IP addresses) | **Absent** |
| 11 | SSL Certificate | free | HTTPS status code only; no chain, issuer or dates | **Absent** |
| 12 | Port Scan | free | `nmap` entry in `ToolCatalog` (`-sn`, discovery only); raw text | **Wrapper** |
| 13 | Path Check | free | HTTPS 443 check only; no arbitrary `host:port` | **Partial** |
| 14 | Subnet Calculator | free | Prefix lengths parsed for interface display only | **Absent** |
| 15 | iperf3 | pro | Menu item opens iperf.fr; no client | **Absent** |
| 16 | Network Monitor | free | `InterfacesView` + `SystemInterfaceScanner`: addresses, gateway, DNS, VPN interfaces, RX/TX counters | **Parity** |
| 17 | Uptime Monitor | pro | — (menu-bar alerts cover Wi-Fi only) | **Absent** |
| 18 | LAN Scanner + Network Guard | pro | `LiveClientDiscoveryView` extracts MACs from a monitor-mode capture; no ARP/mDNS sweep, IPs, vendor table, ports or new-device alerts | **Partial** |
| 19 | Wi-Fi Analyzer | pro | Quality score, RSSI/noise/SNR, security audit, diagnostics | **Ahead** |
| 20 | Wi-Fi Networks | pro | Scan, IE decode, 6 GHz/Wi-Fi 7, ranked channel advice, survey | **Ahead** |

Summary: **2 ahead, 1 at parity, 6 partial, 3 wrappers, 8 absent.**

Two caveats on this matrix:

- `ToolConsoleView` is reachable from the toolbar **Tools** menu, but it only
  runs a binary and prints raw text. The `ping`, `traceroute`, `mtr`, `nmap` and
  `iperf3` entries have no parsed result table and no history.
- Netutilus's free tier is broader than its Pro tier. LanFi's diagnostics cover
  the *checks* of Internet Check but not its **one-line verdict**, which is the
  actual product.

## Cross-cutting gaps

These block parity regardless of how many tool screens are added.

### 1. Native probe layer instead of `Process`

Current shell-outs: `/sbin/ping` (ping, gateway, latency), `/usr/bin/networkQuality`
(speed test), `/usr/sbin/tcpdump` (capture), plus optional `nmap`/`mtr`/`iperf3`/`ssh`.
Text parsing is locale- and macOS-version-fragile, and the approach cannot ship in
a sandbox. Netutilus's claim — "sandboxed, never shells out, results are the app's
own" — requires replacing those with:

- ICMP echo over an unprivileged datagram ICMP socket, streaming per-probe results;
- TCP connect probes over `NWConnection` (ping and path check);
- DNS record queries (`DNSServiceQueryRecord` or Network.framework) for A/AAAA/MX/
  TXT/NS/SOA/CNAME/SRV/CAA, with a selectable resolver;
- TLS chain inspection with `Security.framework` (issuer, validity, days left);
- a TTL-stepping traceroute/MTR engine with per-hop loss and jitter;
- a bounded-concurrency TCP port prober with a service-name map.

This layer is the prerequisite for roughly a dozen tools. Build it once, behind
injectable protocols, with tests that never touch the network — the same pattern
as `DiagnosticsTransport`.

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

There is no `UserNotifications` usage and no metrics store beyond the 12-entry
diagnostics history. Uptime Monitor and scheduled speed tests need a timestamped
store, notification authorization, and a menu-bar status item. `MenuBarExtra`
and `MenuBarAlertEngine` are the right seams; the missing part is the scheduler
and the store.

### 4. Third-party data sources and privacy

Whois/RDAP, DNS propagation, GeoIP and visual traceroute use external services
(`rdap.org`, six public DNS resolvers, `ipwho.is`). They run only when the user
presses the corresponding action, and `PRIVACY.md` now documents each request.

### 5. Localization and accessibility

Five languages and VoiceOver labels are part of the product standard. Twenty
tools' worth of new strings (including dynamic technical text) is a real cost and
should be budgeted per phase, not at the end.

## Roadmap to parity

Estimates are order-of-magnitude person-days for one experienced macOS developer,
including tests and localization but excluding review time.

### Phase 0 — Native probe layer (prerequisite)

ICMP + TCP + DNS records + TLS chain + traceroute/MTR + port prober, all behind
injectable transports, no `Process` for ping or speed test.

**Exit:** a pure-Swift `NetProbe` module with unit tests; `DiagnosticsEngine` and
the new tools consume it; no shell parsing on the hot path.
**Effort:** 10–15 days.

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
**Effort:** 20–26 days.

### Phase 2 — Monitoring and LAN (Pro-adjacent)

Uptime Monitor (HTTP/TCP checks, interval, notifications, outage history, menu-bar
status), scheduled speed tests, native LAN scanner (ARP table + mDNS/Bonjour +
TCP probe, IP/MAC/vendor/latency, optional ports), Network Guard new-device alerts.
**Effort:** 14–19 days.

### Phase 3 — Data and map

Whois/RDAP, DNS propagation across public resolvers, GeoIP (bundled DB or opt-in
API), visual traceroute with MapKit.
**Effort:** 9–12 days.

### Phase 4 — Distribution

Notarization and/or the sandboxed MAS split, privacy manifest, permissions copy.
**Effort:** 8–12 days plus an Apple Developer Program account.

**Full parity: roughly 61–84 person-days (12–17 weeks).**

## Recommended scope

Cloning all 20 tools would make LanFi a weaker Netutilus; Netutilus's moat is
breadth, LanFi's is Wi-Fi depth. The defensible subset is the troubleshooting
chain that starts from "my Wi-Fi is bad":

1. **Internet Check verdict** — connects LanFi's RF evidence to provider
   attribution. Neither Netutilus nor WiFi Explorer has LanFi's radio data, so
   this is the one place where parity becomes differentiation.
2. **Ping + Traceroute + MTR**, native and charted — replaces the raw Tool
   Console and is the everyday workflow.
3. **DNS Lookup + Path Check + Port Scan + SSL** — share the Phase 0 probe layer;
   cheap once the core exists.
4. **Uptime Monitor** with menu-bar status — closest thing to a paid feature and
   reuses the existing `MenuBarExtra`.

**Superseded:** Whois, GeoIP, DNS Propagation, Visual Traceroute, LAN
Scanner/Guard and scheduled speed tests have since shipped as part of the
toolkit expansion.

This subset is Phase 0 plus about 25–30 days of Phase 1–2 work — roughly
**8 weeks**, versus 3–4 months for the full catalogue.

## Acceptance criteria for "Netutilus parity"

- [ ] No `Process` or shell-out for ping, speed test, DNS, port/path checks,
      traceroute or TLS; every probe is sandbox-viable.
- [ ] 13 free tools have first-class UI, parsed results, copy and export.
- [ ] Internet Check returns a Wi-Fi/router/provider verdict with evidence.
- [ ] Uptime Monitor runs scheduled checks, notifies, and keeps outage history.
- [ ] Speed Test shows a bufferbloat grade and history.
- [ ] LAN Scanner lists IP/MAC/vendor/latency/ports without monitor mode.
- [ ] All new strings localized in the five shipped languages, with VoiceOver
      labels.
- [ ] Distribution is notarized and/or sandboxed for the Mac App Store.
