#!/usr/bin/env bash
# UI smoke test: build the Debug app, run its headless bundle check and capture
# two real screens through the in-app snapshot harness. No Screen Recording
# permission and no UI automation framework; a crash, a blank window or a view
# that cannot be constructed fails the step. Screenshots are kept for review.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${RUNNER_TEMP:-/tmp}/lanfi-ui-smoke"
mkdir -p "$OUT"

xcodebuild build \
  -project LanFi.xcodeproj \
  -scheme LanFi \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO >/dev/null

BIN=build/DerivedData/Build/Products/Debug/LanFi.app/Contents/MacOS/LanFi
test -x "$BIN" || { echo "Missing app binary: $BIN" >&2; exit 1; }

# Bundle and resource checks, then two screens: the all-band workspace and the
# newest toolkit surface. Fixed language, theme and size keep the result
# comparable between runs.
"$BIN" --smoke-test | tee "$OUT/smoke.json"

# The snapshot harness needs a WindowServer session. On a machine where the
# shell has none (a background agent) AppKit never reaches the run loop, so a
# hard limit turns a hang into a readable failure instead of a dead job.
run_with_timeout() {
  local seconds="$1"
  shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$seconds" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "Timed out after ${seconds}s: $*" >&2
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

BASE_ARGS=(-LanFi.hasCompletedFirstRun YES -AppleLanguages '(en)' -AppleLocale en_US --demo)
run_with_timeout 90 "$BIN" "${BASE_ARGS[@]}" --appearance light --window-size 1180x760 \
  --snapshot-toolkit "$OUT/toolkit.png" --tool wifiAnalyzer --delay 3
run_with_timeout 90 "$BIN" "${BASE_ARGS[@]}" --appearance light --window-size 1180x760 \
  --snapshot-toolkit "$OUT/route-monitor.png" --tool routeMonitor --delay 2

for shot in toolkit route-monitor; do
  file="$OUT/$shot.png"
  test -s "$file" || { echo "Snapshot is empty: $file" >&2; exit 1; }
  sips -g pixelWidth -g pixelHeight "$file" | tee -a "$OUT/screenshots.txt"
done

printf 'UI smoke passed; screenshots in %s\n' "$OUT"
