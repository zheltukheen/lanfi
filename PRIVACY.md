# Privacy

LanFi is a local-first macOS utility. It does not include analytics, crash
reporting, advertising, accounts, or any network telemetry.

## What LanFi accesses

- **Wi-Fi scan results** (SSID, BSSID, RSSI, channel, information elements) via
  Apple's public CoreWLAN framework. These exist only in memory while the app
  is running.
- **Location Services authorization**, required by macOS before it reveals
  SSID/BSSID values to an application. LanFi requests *always* authorization
  because CoreWLAN exposes the data through that permission. LanFi does not
  request, read, or store geographic coordinates, and no location data leaves
  the Mac.
- **UserDefaults** to remember window layout, column configuration, refresh
  interval, filters and display preferences on your Mac.

- **Route table and resolver configuration** (`netstat`, `scutil --dns`) to show
  whether a VPN is up and whether DNS or IPv6 appears to bypass it. These are
  local reads only: LanFi never contacts a VPN provider and never reads or stores
  credentials.

## Network requests

LanFi makes only these outbound requests:

- **Sparkle update check** to `github.com` for the signed `appcast.xml` and, if
  you accept an update, the release archive. No identifiers are added.
- **Optional diagnostics** you explicitly run: a DNS lookup and HTTPS check of
  `captive.apple.com`, plus ICMP echo to the default gateway and `1.1.1.1`.
  These requests prove connectivity and measure latency; their results stay on
  your Mac and are never uploaded.
- **Tools you explicitly run** contact the host you enter (ping, traceroute,
  MTR, DNS, port scan, SSL, path check, iperf3, uptime checks).
- **DNS Propagation** sends the queried name to six public resolvers
  (Cloudflare, Google, Quad9, OpenDNS, Level3 and a Cloudflare secondary).
- **Whois** sends the domain or IP to `rdap.org`; **GeoIP** and the map in
  Visual Traceroute send public hop addresses to `ipwho.is`.
- **Connectivity watchdog** (on by default, can be turned off in Settings →
  General) sends one plain HTTP GET to the captive-portal endpoint
  (`captive.apple.com`, falling back to `www.apple.com`) every 15 s–5 min to
  tell an online link from a captive portal or a dead WAN. It sends no payload
  and no identifiers, and the verdict stays on your Mac.
- **Gateway and DNS integrity guard** (on by default, can be turned off in
  Settings → General) reads the default gateway's MAC from the local ARP table
  and sends one A query for `captive.apple.com` directly to Cloudflare
  (`1.1.1.1`) every 10 minutes, then compares it with the system resolver's
  answer for the same name. The query carries no identifier; the comparison
  stays on your Mac.
- **Speed Test** uses Apple's `networkQuality` command. These third-party
  requests are made only when you press the corresponding button; LanFi does
  not attach an account, device identifier or telemetry payload.

Traffic totals are kept locally in `traffic-accounting.json` and per-app hourly
totals in `app-traffic-history.json` (byte counts only, seven days, only while
Process Traffic is enabled); they never leave the Mac and can be cleared from the Data usage card or by deleting the file.

There is no telemetry, cloud sync, remote logging or third-party analytics SDK.
Exports (CSV/JSON/PCAP) and saved sessions/annotations/surveys are written only
to local paths you choose or to LanFi's Application Support directory.

## Data retention

Scan data is kept in memory and discarded when LanFi quits, unless you explicitly
save a session, annotation or survey. Preferences and saved files remain on your
Mac until you remove them (the Homebrew cask `zap` stanza removes them).

## Contact

Open an issue at <https://github.com/zheltukheen/lanfi/issues> for privacy
questions.
