#!/usr/bin/env bash
# UI smoke test: build the Debug app, lay out every available tool screen in
# `--ui-smoke` (no WindowServer required) and run the bundle checks with
# `--smoke-test`. Optional screenshot capture (`LANFI_UI_SNAPSHOTS=1`) needs a
# logged-in GUI session and is therefore not part of CI.
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

# Hard limit: a view that never finishes layout must fail the step instead of
# hanging the job. AppKit can block indefinitely when the shell has no GUI
# session, and the app's normal launch would then never reach the check.
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

run_with_timeout 120 "$BIN" --ui-smoke | tee "$OUT/ui-smoke.json"
"$BIN" --smoke-test | tee "$OUT/smoke.json"

if [ "${LANFI_UI_SNAPSHOTS:-0}" != "1" ]; then
  printf 'UI smoke passed; set LANFI_UI_SNAPSHOTS=1 to also capture screenshots\n'
  exit 0
fi

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
