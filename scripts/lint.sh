#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=(LanFiApp.swift Models Services Utils ViewModels Views Tests)
if xcrun --find swift-format >/dev/null 2>&1; then
    FORMAT=(xcrun swift-format)
else
    FORMAT=(swift-format)
fi

"${FORMAT[@]}" lint --recursive --configuration .swift-format --no-color-diagnostics "${SOURCES[@]}"
