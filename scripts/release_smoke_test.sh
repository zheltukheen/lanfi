#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/LanFi-Universal/LanFi.app}"
test -d "$APP" || { echo "Missing app: $APP" >&2; exit 1; }
BIN="$APP/Contents/MacOS/LanFi"
test -x "$BIN" || { echo "Missing executable: $BIN" >&2; exit 1; }

ARCHS="$(lipo -archs "$BIN")"
echo "Architectures: $ARCHS"
echo "$ARCHS" | grep -q arm64
echo "$ARCHS" | grep -q x86_64
codesign --verify --deep --strict --verbose=2 "$APP"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
test -f "$APP/Contents/Resources/oui"
test -f "$APP/Contents/Resources/ru.lproj/Localizable.strings"
LOG_DIR="${RUNNER_TEMP:-/tmp}"
"$BIN" --smoke-test | tee "$LOG_DIR/lanfi-smoke.json"
