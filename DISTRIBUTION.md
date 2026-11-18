# Distribution

## Signing identity and Location Services

LanFi reads SSIDs and BSSIDs through CoreWLAN, which macOS gates behind Location
Services. TCC stores that grant against the app's code-signing identity.

Ad-hoc builds (`codesign --sign -`) get a different identity when the binary is
rebuilt. After an update, macOS may therefore treat the new build as a different
app: Location Services still shows LanFi as enabled, but scans return rows with
empty SSID and BSSID. LanFi detects that case as `identifiersHidden` and shows an
explicit banner instead of an empty table.

This is expected for local development builds, not a scanning bug. To recover:

1. Quit LanFi.
2. Open System Settings → Privacy & Security → Location Services.
3. Remove LanFi from the list, then launch the new build and allow access again.

A Developer ID signed and notarized build keeps a stable identity across
updates, so the grant normally survives. Changing the bundle identifier or
signing team also resets the grant.

## Release checklist

- Sign nested Sparkle/XPC code individually, with hardened runtime and a
  timestamp.
- Submit with `notarytool submit --wait`; staple both the DMG and the ZIP.
- On a clean Mac, verify: Gatekeeper launch, one Location Services grant,
  SSID/BSSID present, and the grant still present after replacing the app with a
  newer signed build.
