# Reference apps review — November 2026

Status: **input to [`GAP_ANALYSIS_2026-11.md`](GAP_ANALYSIS_2026-11.md)**.
Baseline: LanFi 5.3.0. Four public sources were read on 2026-11-16 and compared
with the shipped code, not with the roadmap text.

This review covers a different slice of the market than
[`COMMERCIAL_GAP.md`](COMMERCIAL_GAP.md) (paid analyzers) and
[`NETUTILUS_PARITY.md`](NETUTILUS_PARITY.md) (network toolkit): a buyer's guide,
two menu-bar utilities and one long-lived Mac scanner. Their shared lesson is
that **presentation and continuity sell the product**, while the analyzer depth
LanFi already has is mostly invisible in a screenshot.

## The four references

| Reference | What it is | What it does better than LanFi today | What LanFi already matches |
| --- | --- | --- | --- |
| [Unstore: 7 Wi-Fi analyzers](https://ru.unstore.io/discover/best-wifi-analyzer-apps-desktop) | Buying guide over NetSpot, inSSIDer, Acrylic, WiFi Explorer, Vistumbler, Homedale, Ekahau | Names the five criteria buyers check: all-band chart with obvious overlap, live RSSI tracking, heatmap, hardware detail (link rate, MCS, width, cipher, OUI, PHY), 6E/7 support | All five are implemented, but hardware detail is spread over columns and inspectors; there is no single all-band overlap view |
| [NetWorker Pro](https://sascha-simon.com/ru/apps/networker-pro) | Menu-bar network meter | Throughput in the menu bar, day/week/month/total traffic accounting, public IP + country, open TCP/UDP connections, per-process traffic, unit choice | Quality score, diagnostics, GeoIP tool, LAN Scanner |
| [AirRadar 8](https://www.koingosw.com/products/airradar/) | Long-lived Mac scanner (8.0, Jan 2026) | GPS map of networks with saved/shared scan maps, signal+noise graph modes, colour labels, favourites, "time ago", editable full-breakdown window, auto-join, spoken SSIDs, multiple Wi-Fi cards | Labels/tags/notes, saved sessions, monitor timeline, menu-bar alerts, PCAP, vendor DB |
| [PeakHour 6](https://appstorrent.ru/2633-peakhour.html) | Menu-bar traffic visualizer | Sparkline graph in the menu bar, live per-interface and per-device cards, SNMP/UPnP polling of router/NAS, latency strip | Network Monitor interfaces, Uptime Monitor, speed test history |

## 1. Unstore buyer's guide

The article is written for people choosing their first analyzer, and its
checklist is the clearest public statement of what a screenshot has to prove:

1. **Band/channel visualization** — "clean charts showing every nearby network on
   2.4, 5 and 6 GHz at once, with overlap obvious at a glance."
2. **Real-time signal tracking** — RSSI over time, to catch drops a snapshot
   misses.
3. **Heatmap or site survey** — walk the floor plan, record signal per point.
4. **Hardware detail** — link rate, MCS index, channel width, cipher, OUI
   vendor, PHY mode.
5. **Wi-Fi 6/6E/7** — 6 GHz detection and honest link rates on 7 hardware.

LanFi satisfies 2, 3 and 5, and covers 4 as a catalogue of 44 columns. It fails
1 as a first impression: `SpectrumView` is per-band, so "all bands at once" —
what every competing screenshot shows — requires switching tabs. That is a
**presentation** gap, not a data gap, and it is the cheapest conversion win in
this document.

Hardware detail that is genuinely missing (as opposed to merely scattered):

- negotiated link rate, PHY mode and MCS/NSS of the **connected** link over
  time (today `DiagnosticsEngine` reads `transmitRate()` once per run);
- a "Link" inspector block that puts rate, MCS, width, streams and cipher in
  one place.

## 2. NetWorker Pro

Six features, of which LanFi has one (public IP via the GeoIP tool):

- throughput in the menu bar, with configurable readout;
- traffic accounting per day / week / month / total;
- public IP and country in the main window;
- open TCP/UDP connections list;
- per-process traffic;
- unit and bit/byte preference.

The menu-bar meter is the headline: it makes the app permanently useful and
permanently visible without opening a window. LanFi's `MenuBarExtra` already
exists (alerts, connected network, diagnostics, uptime, recommendation) but
shows no live numbers and no graph.

Traffic accounting needs `getifaddrs` byte counters plus a sampler; per-process
traffic needs `nettop`-class data, which on macOS means either the private
`NET_RT_IFLIST2` path or shelling out to `nettop -P` and parsing. That is a
privacy-sensitive, higher-risk screen — plan it as a separate, read-only step.

## 3. AirRadar 8

The 8.0 release notes are unusually explicit about what users complained about,
and every item is a presentation issue:

- a network edit window with the **full breakdown presented nicely** instead of
  just notes;
- **3 graph modes**: noise, signal, or both;
- **"time ago"** formatting when the scan interval is short;
- wording fixes ("Unavailable" instead of "Dead");
- auto-sized list columns after the first scan;
- scan keeps working while location permission is pending.

Product-level capabilities LanFi lacks:

- **GPS map**: networks pinned on a map, updated as a better signal is found,
  saved per trip and shareable; open networks green, closed red;
- **collections/history** of scan maps, clearable;
- **auto-join the best network**;
- **spoken SSIDs** and sound alerts on new networks;
- **multiple Wi-Fi cards**: choose which card scans and joins;
- congested-channel statistics as a first-class screen (LanFi has it in Insights).

Auto-join and Keychain password storage are deliberately out of scope: joining
networks on the user's behalf and storing credentials turns a read-only analyzer
into a privileged actor with a new failure surface. Speak-alerts are low value.
GPS capture is worth having because it is the only feature here that produces an
artifact a user can hand to someone else — and because `VisualTraceroute` already
links MapKit, so the dependency and the permission story exist.

## 4. PeakHour 6

PeakHour's value is entirely visual: a menu-bar sparkline, a large live graph,
one card per monitored target with its own mini graph, and latency alongside
throughput. Targets come from SNMP or UPnP on the router/NAS, which is the one
capability LanFi has no path to today (no SNMP client, no SSDP browse).

Two transferable patterns:

- **menu-bar mini graph** — draw the last N samples with a `Canvas` in the
  `MenuBarExtra` label;
- **card with sparkline per target** — exactly the shape Uptime Monitor and
  Remote Sensors need; today they are tables.

SNMP/UPnP polling is a legitimate differentiator for a toolkit app (router CPU,
WAN counters, NAS throughput) but it is a new protocol family with vendor
quirks. Keep it in the "later" bucket.

## Cross-cutting design observations

1. **The menu bar is a product surface.** Three of the four references ship a
   meaningful menu-bar presence; all of LanFi's summaries are text. A compact
   sparkline plus one number converts better than a list of labels.
2. **One screen must prove the product.** Unstore reduces the buying decision to
   one all-band chart. LanFi's best screen (Insights) still requires reading
   cards; a single "RF overview" with all bands and overlap is the missing hero
   shot.
3. **Relative time and plain words.** AirRadar's changelog is a list of wording
   and formatting fixes, and its reviewers complain that channel numbers are
   unexplained. LanFi has strong explanation text in findings but not next to
   the columns themselves.
4. **The detail window is the product.** AirRadar replaced "just notes" with a
   full breakdown window; LanFi's inspector is good but split across six
   sections and three tabs, and there is no printable per-network page.
5. **Visual consistency is uneven.** `ToolkitCard`, `ToolkitStatusPill` and
   `ToolkitSectionLabel` exist, but the Wi-Fi workspace hand-rolls its cards,
   radii (8/10/12) and tints (`Color.orange.opacity(0.10)`,
   `Color.secondary.opacity(0.12)` and friends) per view. Nothing is broken;
   nothing looks designed as one system.

## What this adds to the plan

Mapped to the numbering in [`GAP_ANALYSIS_2026-11.md`](GAP_ANALYSIS_2026-11.md):

| Delta | Plan item | Why it is worth doing |
| --- | --- | --- |
| All-band RF overview with overlap | P1.11 | The single screenshot that competes with every rival |
| Menu-bar live meter (throughput + mini graph) | P0.6 | Permanent presence; PeakHour/NetWorker pattern |
| Connections and per-process traffic | P1.8 | NetWorker parity; explains "what is using my network" |
| GPS scan map and saved collections | P1.9 | The only shareable artifact in AirRadar |
| Connected-link telemetry (rate, MCS, PHY, noise chart) | P2.6 | Closes the Unstore "hardware detail" criterion honestly |
| Design system, hero screen, density, wording, assets | D1–D8 | Turns delivered depth into visible quality |

## Sources

- <https://ru.unstore.io/discover/best-wifi-analyzer-apps-desktop>
- <https://sascha-simon.com/ru/apps/networker-pro>
- <https://www.koingosw.com/products/airradar/> (version history and reviews)
- <https://appstorrent.ru/2633-peakhour.html> (product description and
  screenshots of PeakHour 6)
