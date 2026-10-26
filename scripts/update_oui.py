#!/usr/bin/env python3
"""Build Resources/oui from the IEEE registries and the Wireshark manuf file.

The database stores 24-bit (MA-L), 28-bit (MA-M) and 36-bit (MA-S) prefixes so
WiFA can resolve an access point's vendor as precisely as the registries allow.
Longest-prefix matching happens in Utils/OUIParser.swift.

Usage:
    python3 scripts/update_oui.py                 # download all sources
    python3 scripts/update_oui.py file1 file2     # local CSV/manuf/OUI files

Sources:
    https://standards-oui.ieee.org/oui/oui.csv
    https://standards-oui.ieee.org/oui28/mam.csv
    https://standards-oui.ieee.org/oui36/oui36.csv
    https://www.wireshark.org/download/automated/data/manuf
"""

from __future__ import annotations

import csv
import io
import os
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen

IEEE_URLS = {
    "MA-L": "https://standards-oui.ieee.org/oui/oui.csv",
    "MA-M": "https://standards-oui.ieee.org/oui28/mam.csv",
    "MA-S": "https://standards-oui.ieee.org/oui36/oui36.csv",
}
WIRESHARK_URL = "https://www.wireshark.org/download/automated/data/manuf"

OUI_TEXT_RE = re.compile(
    r"^\s*([0-9A-Fa-f]{2})[-: ]?([0-9A-Fa-f]{2})[-: ]?([0-9A-Fa-f]{2})\s*"
    r"\((?:hex|base 16)\)\s*(.+?)\s*$"
)
HEX_RE = re.compile(r"^[0-9A-F]+$")

SKIP_VENDORS = {
    "",
    "-",
    "PRIVATE",
    "IEEE REGISTRATION AUTHORITY",
    "IEEE",
}


def fetch(url: str) -> str:
    request = Request(url, headers={"User-Agent": "WiFA-OUI-Updater/2.0"})
    with urlopen(request, timeout=90) as response:
        return response.read().decode("utf-8", errors="ignore")


def clean_vendor(value: str) -> str:
    value = value.strip().strip('"').strip()
    value = re.sub(r"\s+", " ", value)
    value = value.strip(" ,")
    return value


def normalize_key(value: str) -> str:
    key = "".join(char for char in value.upper() if char in "0123456789ABCDEF")
    return key


def is_skipped(vendor: str) -> bool:
    return vendor.upper() in SKIP_VENDORS


def parse_ieee_csv(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames or "Assignment" not in reader.fieldnames:
        return out

    for row in reader:
        key = normalize_key(row.get("Assignment") or "")
        vendor = clean_vendor(row.get("Organization Name") or "")
        if len(key) in (6, 7, 9) and not is_skipped(vendor):
            out[key] = vendor
    return out


def parse_wireshark(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) < 2:
            continue

        prefix = columns[0].strip()
        vendor = clean_vendor(columns[-1]) or clean_vendor(columns[1])
        if not prefix or not vendor or is_skipped(vendor):
            continue

        base, _, mask = prefix.partition("/")
        key = normalize_key(base)
        if mask.isdigit():
            bits = int(mask)
            if bits < 24 or bits > 36 or bits % 4 != 0:
                continue
            key = key[: bits // 4]
        if len(key) not in (6, 7, 8, 9):
            continue
        out[key] = vendor
    return out


def parse_oui_text(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        match = OUI_TEXT_RE.match(line)
        if not match:
            continue
        key = normalize_key("".join(match.groups()[:3]))
        vendor = clean_vendor(match.group(4))
        if len(key) == 6 and not is_skipped(vendor):
            out[key] = vendor
    return out


def parse_source(text: str, name: str = "") -> dict[str, str]:
    if "Registry,Assignment" in text[:200] or "Organization Name" in text[:200]:
        return parse_ieee_csv(text)
    if "(hex)" in text[:2000] or "(base 16)" in text[:2000]:
        return parse_oui_text(text)
    return parse_wireshark(text)


def load_inputs(arguments: list[str]) -> list[tuple[str, str]]:
    if arguments:
        inputs = []
        for argument in arguments:
            if re.match(r"^https?://", argument):
                inputs.append((argument, fetch(argument)))
            else:
                inputs.append((argument, Path(argument).read_text(encoding="utf-8", errors="ignore")))
        return inputs

    inputs = [("wireshark manuf", fetch(WIRESHARK_URL))]
    for registry, url in IEEE_URLS.items():
        inputs.append((f"IEEE {registry}", fetch(url)))
    return inputs


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    output_path = Path(os.environ.get("OUI_OUTPUT", repo_root / "Resources" / "oui"))

    try:
        inputs = load_inputs(sys.argv[1:])
    except Exception as error:  # noqa: BLE001 - surfaced to the operator
        print(f"Failed to download OUI data: {error}", file=sys.stderr)
        return 1

    # Wireshark first, then IEEE from least to most specific. Later writes win,
    # so official IEEE names replace generic/short manuf aliases.
    table: dict[str, str] = {}
    for name, text in inputs:
        parsed = parse_source(text, name)
        overlap = len(set(parsed) & set(table))
        table.update(parsed)
        print(f"{name}: {len(parsed)} prefixes ({overlap} updated)")

    if len(table) < 30_000:
        print(
            f"Refusing to write only {len(table)} prefixes; sources look incomplete.",
            file=sys.stderr,
        )
        return 2

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for key in sorted(table, key=lambda value: (len(value), value)):
            handle.write(f"{key}\t{table[key]}\n")

    by_length: dict[int, int] = {}
    for key in table:
        by_length[len(key)] = by_length.get(len(key), 0) + 1
    print(f"Wrote {len(table)} prefixes to {output_path}")
    print("By prefix length: " + ", ".join(f"{length}: {count}" for length, count in sorted(by_length.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
