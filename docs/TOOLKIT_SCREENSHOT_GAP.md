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
| Port Scan | TCP connect, presets, service versions, optional 10 UDP probes | Done. |
| Path Check | Host + up to 32 ports, presets, per-port results | Done. |
| Subnet Calculator | CIDR, IP + netmask and “This Mac” network | Done. |
| iperf3 | Host/port/duration/direction, saved servers, persisted history | Done. |
| Uptime Monitor | HTTP/TCP/TLS/DNS targets, history, notifications | Done; richer mail/DMARC monitoring remains optional. |
| Network Monitor | Overview + Routes tabs, current IPv4 route table | Done; change log remains. |
| LAN Scanner | ARP/TCP fallback, vendor, ports, Guard, per-device service versions | Done. |
| Internet Check | Verdict, path, details, Quick/Full with speed | Done. |
| Ping | ICMP/TCP, count/interval, continuous mode, TCP port presets, chart + table | Done; multi-chart layout remains optional. |
| Traceroute | Max hops, probes, timeout, resolve names, richer table | Done. |
| MTR | Rounds, loss/jitter table, latency graph, stddev, continuous mode | Done. |

## Delivery order

1. **Shell**: sidebar search + Recent — done.
2. **Missing data tools**: DNS Propagation, Whois/RDAP, GeoIP — done; they
   reuse the existing DNS client and `URLSession`, so no new shelling out.
3. **Visual Traceroute**: traceroute runner + GeoIP + MapKit — done.
4. **Depth on existing tools**: Ping continuous/presets, Traceroute options
   and MTR graph/stddev are done. DNS mail/reports and Speed Test tabs are
   also done; Path Check multi-port/presets and Subnet IP+mask/This Mac are
   done; Port service-version detection and iperf3 saved servers/history are
   done; Network Monitor Routes, LAN service detection, MTR continuous,
   Port Scan UDP and Uptime TLS/DNS targets are done. Remaining: optional
   mail/DMARC monitoring and the final design pass.
5. **Design pass**: consistent tool header, Port Scan proxy warning and
   iperf3 control layout done; Internet Check Quick/Full done. Final
   cross-screen audit remains.

Phases 1–3 are shipped. Phase 4 and the final design pass remain.
Each phase gets tests for its pure logic, a screenshot check and a commit.
