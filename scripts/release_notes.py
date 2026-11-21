#!/usr/bin/env python3
"""Build GitHub release notes from the CHANGELOG sections.

By default the body is the section of the version being released. With
``--since X.Y.Z`` (or ``RELEASE_NOTES_SINCE``) every section newer than that
version is folded in as well, so a release published after a run of unshipped
versions still lists everything that changed since the last published build.
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

VERSION_RE = re.compile(
    r"^##\s+(?P<version>[0-9]+(?:\.[0-9]+){2})"
    r"(?:\s*[—–-]\s*(?P<date>[0-9]{4}-[0-9]{2}-[0-9]{2}))?"
)

INSTALL_AND_VERIFY = """### Install
1. Download `LanFi.dmg` (or `LanFi.zip`).
2. Drag LanFi to Applications.
3. Open LanFi and allow Location Services when prompted — macOS requires it to reveal SSIDs/BSSIDs.
4. If Gatekeeper blocks the ad-hoc signed build, right-click the app and choose Open.

The always-latest build lives at
<https://github.com/zheltukheen/lanfi/releases/latest/download/LanFi.dmg>
(`LanFi.zip` for the archive). The same unversioned names are used inside each
tagged release.

### Verify
The SHA-256 checksums are attached as `LanFi.sha256`."""


def parse_sections(text: str) -> list[dict[str, str]]:
    """Every ``## X.Y.Z`` section, newest first, as version/date/body."""
    sections: list[dict[str, str]] = []
    current: dict[str, object] | None = None
    for line in text.splitlines():
        match = VERSION_RE.match(line)
        if match:
            if current is not None:
                sections.append(_finish(current))
            current = {
                "version": match.group("version"),
                "date": match.group("date") or "",
                "lines": [],
            }
            continue
        if current is not None:
            current["lines"].append(line)  # type: ignore[union-attr]
    if current is not None:
        sections.append(_finish(current))
    return sections


def _finish(section: dict[str, object]) -> dict[str, str]:
    lines = section["lines"]  # type: ignore[assignment]
    return {
        "version": str(section["version"]),
        "date": str(section["date"]),
        "body": "\n".join(lines).strip(),  # type: ignore[arg-type]
    }


def parse_args(argv: list[str]) -> tuple[str, str]:
    tag = os.environ.get("GITHUB_REF_NAME", "")
    version = tag.lstrip("v") if tag else ""
    since = os.environ.get("RELEASE_NOTES_SINCE", "").strip().lstrip("v")

    positional: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--since":
            if i + 1 >= len(argv):
                print("--since needs a version", file=sys.stderr)
                raise SystemExit(2)
            since = argv[i + 1].lstrip("v")
            i += 2
            continue
        if arg.startswith("--since="):
            since = arg.split("=", 1)[1].lstrip("v")
            i += 1
            continue
        if arg.startswith("-"):
            print(f"Unknown option {arg}", file=sys.stderr)
            raise SystemExit(2)
        positional.append(arg)
        i += 1

    if not version and positional:
        version = positional[0].lstrip("v")
    if not version:
        print("Set GITHUB_REF_NAME or pass a version argument.", file=sys.stderr)
        raise SystemExit(2)
    if len(positional) > 1:
        print("Unexpected extra argument", file=sys.stderr)
        raise SystemExit(2)
    return version, since


def summarize(section: dict[str, str]) -> str:
    date = f" — {section['date']}" if section["date"] else ""
    return (
        f"<details>\n<summary><b>{section['version']}</b>{date}</summary>\n\n"
        f"{section['body']}\n\n</details>"
    )


def main() -> int:
    version, since = parse_args(sys.argv[1:])

    changelog = pathlib.Path(os.environ.get("CHANGELOG", "CHANGELOG.md"))
    if not changelog.exists():
        print(f"{changelog} not found", file=sys.stderr)
        return 2

    sections = parse_sections(changelog.read_text(encoding="utf-8"))
    index = next(
        (i for i, section in enumerate(sections) if section["version"] == version), None
    )
    if index is None:
        print(f"No CHANGELOG section for {version}", file=sys.stderr)
        return 1

    target = sections[index]
    if not target["body"]:
        print(f"CHANGELOG section for {version} is empty", file=sys.stderr)
        return 1

    # Sections are newest first, so everything before the target was written
    # after it. Stop at the version that was already published on its own.
    carried: list[dict[str, str]] = []
    for section in sections[index + 1 :]:
        if since and section["version"] == since:
            break
        carried.append(section)

    parts = [f"## LanFi {version}", "", target["body"]]
    if carried:
        years = "version" if len(carried) == 1 else "versions"
        span = carried[0]["version"]
        if len(carried) > 1:
            span = f"{carried[-1]['version']} through {carried[0]['version']}"
        parts += [
            "",
            f"### Everything since {since}",
            "",
            f"{len(carried)} earlier {years} ({span}) never shipped a release of "
            "their own, so their entries are collected here. Expand a version to "
            "read its notes.",
            "",
            "\n\n".join(summarize(section) for section in carried),
        ]
    parts += ["", INSTALL_AND_VERIFY, ""]

    body = "\n".join(parts)
    output = pathlib.Path(os.environ.get("OUTPUT", "release_notes.md"))
    output.write_text(body, encoding="utf-8")
    extra = f"; {len(carried)} carried section(s) since {since}" if carried else ""
    print(f"Wrote {output} ({len(body)} chars from CHANGELOG{extra})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
