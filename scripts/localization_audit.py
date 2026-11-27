#!/usr/bin/env python3
"""Report localization coverage for LanFi.

Two questions, two answers:

1. Does every locale have the same keys as `en`?  A key that exists only in
   `en` is a visible English string in that language.
2. Which UI literals in the Swift sources never made it into `en` at all?  Those
   fall back to their English text in every language, so they are the real
   translation backlog.

Usage:
    python3 scripts/localization_audit.py            # summary
    python3 scripts/localization_audit.py --list     # every missing key
    python3 scripts/localization_audit.py --strict   # exit 1 when anything is missing
"""

from __future__ import annotations

import argparse
import glob
import io
import re
import sys

LOCALES = ["en", "de", "fr", "ru", "zh-Hans"]
ROOT = "Resources"
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"(?:[^"\\]|\\.)*";\s*$')

# Literals that reach SwiftUI's localization machinery. Interpolated literals
# are skipped: their runtime key is built from the format, not the source text.
UI_LITERAL = [
    re.compile(
        r'(?:Text|Button|Label|Toggle|TextField|Picker|AppButton|AppIconButton'
        r'|ToolbarIconButton|Link|Stepper|NavigationLink|Menu|TextEditor)\(\s*'
        r'"((?:[^"\\]|\\.)*)"'
    ),
    re.compile(r'localized:\s*\n?\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'(?:\.help|accessibilityLabel)\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'(?:title|message|subtitle|placeholder):\s*\n?\s*"((?:[^"\\]|\\.)*)"'),
]
SKIP_PREFIXES = ("http://", "https://", "x-apple.")

# Sample values and units that appear as literals in previews and fields
# (`AA:BB:CC:DD:EE:FF`, `1.1.1.1`, `-70 dBm`, `192.168.1.20`) are data, not UI
# copy, so they are not translation debt.
SKIP_SHAPES = (
    re.compile(r"^[-+]?\d"),
    re.compile(r"^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2})+$"),
    re.compile(r"^\d{1,3}(\.\d{1,3}){3}$"),
    re.compile(r"^[^\w\u0400-\u04FF\u4e00-\u9fff]+$"),
)


def load(locale: str) -> dict[str, str]:
    path = f"{ROOT}/{locale}.lproj/Localizable.strings"
    entries: dict[str, str] = {}
    for line in io.open(path, encoding="utf-8"):
        match = ENTRY.match(line.strip())
        if match:
            entries[match.group(1)] = line
    return entries


def source_literals() -> set[str]:
    files = [
        path
        for path in glob.glob("**/*.swift", recursive=True)
        if "/.build/" not in path and not path.startswith("build/")
    ]
    literals: set[str] = set()
    for path in files:
        text = io.open(path, encoding="utf-8").read()
        for pattern in UI_LITERAL:
            literals.update(pattern.findall(text))
    return {
        value
        for value in literals
        if value
        and "\\(" not in value
        and not value.startswith(SKIP_PREFIXES)
        and not any(shape.match(value) for shape in SKIP_SHAPES)
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="print every missing key")
    parser.add_argument("--strict", action="store_true", help="exit 1 on any gap")
    args = parser.parse_args()

    candidates = {locale: load(locale) for locale in LOCALES}
    english = set(candidates["en"])
    literals = source_literals()
    untranslated = sorted(literals - english)

    problems = 0
    print(f"{'locale':8} {'keys':>6} {'missing vs en':>14}")
    for locale in LOCALES:
        keys = set(candidates[locale])
        missing = sorted(english - keys)
        problems += len(missing)
        print(f"{locale:8} {len(keys):6} {len(missing):14}")
        if args.list:
            for key in missing:
                print(f"    - {key}")
    print(f"\nUI literals with no catalogue entry: {len(untranslated)}")
    if args.list:
        for key in untranslated:
            print(f"    - {key}")

    if args.strict and (problems or untranslated):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
