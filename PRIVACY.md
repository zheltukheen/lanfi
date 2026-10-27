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

## Network requests

LanFi makes only these outbound requests:

- **Sparkle update check** to `github.com` for the signed `appcast.xml` and, if
  you accept an update, the release archive. No identifiers are added.
- **Optional diagnostics** you explicitly run: a DNS lookup and HTTPS check of
  `captive.apple.com`, plus ICMP echo to the default gateway and `1.1.1.1`.
  These requests prove connectivity and measure latency; their results stay on
  your Mac and are never uploaded.

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
