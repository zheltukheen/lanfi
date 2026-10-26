#!/usr/bin/env bash
set -euo pipefail

# Notarize an app or DMG with Developer ID + Apple notary service.
# Required environment:
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Name (TEAMID)"
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#
# Usage:
#   ./scripts/notarize.sh app build/LanFi-Universal/LanFi.app
#   ./scripts/notarize.sh dmg build/dist/LanFi-1.7.0.dmg

MODE="${1:-}"
TARGET="${2:-}"
if [[ "$MODE" != "app" && "$MODE" != "dmg" ]] || [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <app|dmg> <path>" >&2
    exit 2
fi
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}"
: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD}"

if [[ "$MODE" == "app" ]]; then
    test -d "$TARGET"
    echo "==> Signing app with Developer ID"
    codesign --force --deep --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$TARGET"
    codesign --verify --deep --strict --verbose=2 "$TARGET"
    ZIP="$(mktemp -d)/notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$ZIP"
    echo "==> Submitting app to Apple notary service"
    xcrun notarytool submit "$ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
    xcrun stapler staple "$TARGET"
    xcrun stapler validate "$TARGET"
else
    test -f "$TARGET"
    echo "==> Signing DMG"
    codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$TARGET"
    echo "==> Submitting DMG to Apple notary service"
    xcrun notarytool submit "$TARGET" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
    xcrun stapler staple "$TARGET"
    xcrun stapler validate "$TARGET"
fi
echo "==> Notarization complete: $TARGET"
