# Signed and notarized distribution

LanFi releases from GitHub Actions are currently ad-hoc signed. That is enough
for Sparkle updates, but Gatekeeper still asks users to confirm the first
launch. The notarization path below is ready to enable with Developer ID
credentials.

## Requirements

- Apple Developer Program membership.
- A **Developer ID Application** certificate installed in the login keychain
  (or imported temporarily in CI).
- An app-specific password for the Apple ID used for notarization.

## Local notarization

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

CODESIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" ./build.sh
./scripts/notarize.sh app build/LanFi-Universal/LanFi.app
./scripts/notarize.sh dmg build/dist/LanFi-<version>.dmg
```

The app must be signed before it is packaged. Re-create the ZIP and DMG after
stapling the app so the distributed copies contain the notarization ticket.
`./scripts/notarize.sh` signs, submits with `notarytool --wait`, staples and
validates the ticket.

## CI secrets

Add these repository secrets when creating the first notarized release:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12` | Base64-encoded `.p12` containing the Developer ID certificate and private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password for the `.p12` |
| `DEVELOPER_ID_IDENTITY` | Full certificate common name, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID used by notarytool |
| `APPLE_TEAM_ID` | Developer Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool |

The release workflow now imports the `.p12` into a temporary keychain, builds
with `CODESIGN_IDENTITY`, runs the headless smoke test, notarizes the app before
packaging, notarizes the DMG after packaging, then writes checksums. If any of
the required secrets are missing the release remains ad-hoc but still ships.

## Verification

```bash
codesign --verify --deep --strict --verbose=2 LanFi.app
spctl --assess --type execute --verbose=4 LanFi.app
xcrun stapler validate LanFi.app
```

`spctl` should report `accepted` and `source=Notarized Developer ID`.
