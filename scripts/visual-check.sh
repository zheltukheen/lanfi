#!/usr/bin/env bash
# Repeatable visual check: builds the Debug app and captures the screens the
# review docs reference in light and dark. Uses the in-app snapshot harness, so
# no Screen Recording permission is needed. `--demo` seeds deterministic
# fixtures (DemoData, Debug-only, never saved), so screenshots do not depend on
# Location access, the current radio or the reviewer's survey files.
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild build \
  -project LanFi.xcodeproj \
  -scheme LanFi \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO >/dev/null

BIN=build/DerivedData/Build/Products/Debug/LanFi.app/Contents/MacOS/LanFi

# Fixed launch arguments: skip onboarding, use seeded data, keep English UI so
# the help window and README read the same. The Material caveat is documented
# in docs/VISUAL_CHECK_2026-11.md.
BASE_ARGS=(-LanFi.hasCompletedFirstRun YES -AppleLanguages '(en)' -AppleLocale en_US --demo)

# Toolkit screens: "<file>:<tool id>" as passed to --tool.
TOOL_SHOTS=(
  "main:wifiAnalyzer"
  "client-analytics:clientAnalytics"
  "site-survey:siteSurvey"
  "open-connections:openConnections"
)

capture() {
  local theme="$1"
  local out="$2"
  mkdir -p "$out"

  local shot
  for shot in "${TOOL_SHOTS[@]}"; do
    "$BIN" "${BASE_ARGS[@]}" --appearance "$theme" \
      --snapshot-toolkit "$out/${shot%%:*}.png" --tool "${shot##*:}" --delay 5
  done
  "$BIN" "${BASE_ARGS[@]}" --appearance "$theme" --snapshot-settings-page "$out/settings-general.png"
  "$BIN" "${BASE_ARGS[@]}" --appearance "$theme" --snapshot-survey "$out/survey-offscreen.png"
  "$BIN" "${BASE_ARGS[@]}" --appearance "$theme" --snapshot-map "$out/survey-map.png"
}

# The top-level set stays the reference used by the docs; dark lives alongside.
capture light screenshots
capture dark screenshots/dark

# Accessibility variant of the settings page: colour-blind palette preview.
"$BIN" "${BASE_ARGS[@]}" -LanFi.colorBlindSafe YES --appearance light \
  --snapshot-settings-page screenshots/settings-colorblind.png

# --- README and site gallery -------------------------------------------------
# 1180×760 points captures 2360×1520 pixels on a Retina Mac, matching the
# width/height attributes in site/index.html. Live probes (ping, port scan, DNS)
# fill the tools; uptime uses the seeded history.
GALLERY_SHOTS=(
  "lanfi-toolkit-ping:ping"
  "lanfi-toolkit-ports:portScan"
  "lanfi-toolkit-dns:dnsLookup"
  "lanfi-toolkit-uptime:uptimeMonitor"
)

to_webp() {
  local source="$1"
  local target="$2"
  if command -v cwebp >/dev/null 2>&1; then
    cwebp -quiet -q 82 "$source" -o "$target"
  elif command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -loglevel error -i "$source" -c:v libwebp -quality 82 "$target"
  else
    printf 'Gallery export needs cwebp or ffmpeg (brew install webp).\n' >&2
    exit 1
  fi
}

mkdir -p build/gallery docs/images site/assets
for shot in "${GALLERY_SHOTS[@]}"; do
  name="${shot%%:*}"
  tool="${shot##*:}"
  "$BIN" "${BASE_ARGS[@]}" --appearance light --window-size 1180x760 \
    --snapshot-toolkit "build/gallery/$name.png" --tool "$tool" --run --delay 9
  to_webp "build/gallery/$name.png" "docs/images/$name.webp"
  cp "docs/images/$name.webp" "site/assets/$name.webp"
done

printf 'Visual check written to %s/screenshots (light, dark/, colour-blind)\n' "$(pwd)"
printf 'Gallery written to docs/images and site/assets (%d images)\n' "${#GALLERY_SHOTS[@]}"
