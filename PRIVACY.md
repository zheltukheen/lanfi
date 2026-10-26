# Privacy

WiFA is a local-first macOS utility. It does not include analytics, crash
reporting, advertising, accounts, or any network telemetry.

## What WiFA accesses

- **Wi-Fi scan results** (SSID, BSSID, RSSI, channel, information elements) via
  Apple's public CoreWLAN framework. These exist only in memory while the app
  is running.
- **Location Services authorization**, required by macOS before it reveals
  SSID/BSSID values to an application. WiFA requests *always* authorization
  because CoreWLAN exposes the data through that permission. WiFA does not
  request, read, or store geographic coordinates, and no location data leaves
  the Mac.
- **UserDefaults** to remember window layout, column configuration, refresh
  interval, filters and display preferences on your Mac.

## What WiFA stores or sends

Nothing is transmitted. Exports (CSV/JSON) are written only to a location you
choose in the save panel. There is no cloud sync, no remote logging and no
third-party SDK.

## Data retention

Scan data is kept in memory and discarded when WiFA quits. Preferences remain
in your macOS user defaults until you remove the app or reset them.

## Contact

Open an issue at <https://github.com/zheltukheen/wifa/issues> for privacy
questions.
