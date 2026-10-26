#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=(WifiAnalyzerApp.swift Models Services Utils ViewModels Views Tests)
if xcrun --find swift-format >/dev/null 2>&1; then
    FORMAT=(xcrun swift-format)
else
    FORMAT=(swift-format)
fi

"${FORMAT[@]}" format --recursive --in-place --configuration .swift-format "${SOURCES[@]}"
