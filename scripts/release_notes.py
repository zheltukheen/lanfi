#!/usr/bin/env python3
"""Build GitHub release notes from the matching CHANGELOG section."""

from __future__ import annotations

import os
import pathlib
import re
import sys

VERSION_RE = re.compile(r"^##\s+(?P<version>[0-9]+\.[0-9]+\.[0-9]+)(?:\s|$|—|-)")


def main() -> int:
    tag = os.environ.get("GITHUB_REF_NAME", "")
    version = tag.lstrip("v") if tag else (sys.argv[1] if len(sys.argv) > 1 else "")
    if not version:
        print("Set GITHUB_REF_NAME or pass a version argument.", file=sys.stderr)
        return 2

    changelog = pathlib.Path(os.environ.get("CHANGELOG", "CHANGELOG.md"))
    if not changelog.exists():
        print(f"{changelog} not found", file=sys.stderr)
        return 2

    collected: list[str] = []
    inside = False
    for line in changelog.read_text(encoding="utf-8").splitlines():
        match = VERSION_RE.match(line)
        if match and match.group("version") == version:
            inside = True
            continue
        if inside and line.startswith("## "):
            break
        if inside:
            collected.append(line)

    section = "\n".join(collected).strip()
    if not section:
        print(f"No CHANGELOG section for {version}", file=sys.stderr)
        return 1

    body = f"""## WiFA {version}

{section}

### Install
1. Download `WiFA-{version}.dmg` (or the `.zip`).
2. Drag WiFA to Applications.
3. Open WiFA and allow Location Services when prompted — macOS requires it to reveal SSIDs/BSSIDs.
4. If Gatekeeper blocks the ad-hoc signed build, right-click the app and choose Open.

### Verify
The SHA-256 checksums are attached as `WiFA-{version}.sha256`.
"""

    output = pathlib.Path(os.environ.get("OUTPUT", "release_notes.md"))
    output.write_text(body, encoding="utf-8")
    print(f"Wrote {output} ({len(section)} chars from CHANGELOG)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
