# Toolkit gaps from the Netutilus screenshots

_Reference: the 20 screenshots supplied on 2026-11-11. This file tracks what is
already at parity, what is missing, and the order in which the gaps are closed._

## Screen-by-screen

| Netutilus screen | LanFi today | Gap / next action |
| --- | --- | --- |
| Sidebar (search, Recent, sections) | Search + persisted Recent shipped | Done. |
| Visual Traceroute | MapKit route + public-hop GeoIP + hop list | Done; private hops stay listed without a pin. |
| Speed Test | Apple `networkQuality`, Result/History tabs, schedule | Done; a richer animated start screen remains optional. |
| DNS Lookup | Records / Mail / Reports tabs, custom resolver, MX/SPF/DMARC/DKIM checks | Done. |
| DNS Propagation | Six resolvers, expected value, table, summary | Done. |
| Whois | RDAP domain/IP report, registrar, statuses, events, nameservers | Done. |
| GeoIP | IP/host, My IP, city/country/ASN/ISP, map link | Done. |
| SSL Certificate | Host/port, chain, trust, days left | Result cards and certificate detail polish. |
| Port Scan | TCP connect, presets, service names | Service/version detection, optional UDP probes, richer presets. |
| Path Check | One host:port | Multi-port field, presets, per-port results. |
| Subnet Calculator | CIDR only | IP + netmask input, IPv6-friendly parsing where possible, “this Mac’s network” shortcut. |
| iperf3 | Host/port/duration/direction | Saved servers, upload/download comparison, result history. |
| Uptime Monitor | HTTP/TCP, history, notifications | Mail/DNS/SSL target types, DMARC/SPF summaries, richer outage detail. |
| Network Monitor | Embedded Interfaces view | Overview / Routes tabs, current route table, change log. |
| LAN Scanner | ARP or ICMP/TCP fallback, vendor, ports, Guard | Service/version detection, richer device inspector, saved-network view. |
| Internet Check | Verdict + path + detail | Quick/Full with speed, richer verdict evidence. |
| Ping | ICMP/TCP, count/interval, continuous mode, TCP port presets, chart + table | Done; multi-chart layout remains optional. |
| Traceroute | Max hops, probes, timeout, resolve names, richer table | Done. |
| MTR | Rounds, loss/jitter table, latency graph, stddev column | Continuous mode remains. |

## Delivery order

1. **Shell**: sidebar search + Recent — done.
2. **Missing data tools**: DNS Propagation, Whois/RDAP, GeoIP — done; they
   reuse the existing DNS client and `URLSession`, so no new shelling out.
3. **Visual Traceroute**: traceroute runner + GeoIP + MapKit — done.
4. **Depth on existing tools**: Ping continuous/presets, Traceroute options
   and MTR graph/stddev are done. DNS mail/reports and Speed Test tabs are
   also done. Remaining: MTR continuous, Port Scan service/UDP, Path Check presets,
   Subnet IP+mask, iperf3 saved servers, Uptime mail checks, Network Monitor
   routes, LAN service detection.
5. **Design pass**: align spacing, inspector placement, toolbar actions and
   empty states with the reference screenshots.

Phases 1–3 are shipped. Phase 4 and the final design pass remain.
Each phase gets tests for its pure logic, a screenshot check and a commit.
