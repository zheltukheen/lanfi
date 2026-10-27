#!/usr/bin/env python3
"""Generate a Sparkle 2 appcast for a single LanFi release."""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import xml.etree.ElementTree as ET


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True, help="Download URL for the zip")
    parser.add_argument("--signature", required=True, help="Sparkle EdDSA signature")
    parser.add_argument("--length", required=True, help="Archive size in bytes")
    parser.add_argument("--notes", default="release_notes.md")
    parser.add_argument("--output", default="appcast.xml")
    parser.add_argument("--minimum-system", default="13.0")
    args = parser.parse_args()

    notes = pathlib.Path(args.notes).read_text(encoding="utf-8") if pathlib.Path(args.notes).exists() else ""
    notes = notes.replace("]]>", "]] >")

    ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
    rss = ET.Element(
        "rss",
        {
            "version": "2.0",
            "xmlns:dc": "http://purl.org/dc/elements/1.1/",
        },
    )
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "LanFi"
    ET.SubElement(channel, "link").text = "https://github.com/zheltukheen/lanfi"
    ET.SubElement(channel, "description").text = "Native macOS Wi-Fi analyzer updates"
    ET.SubElement(channel, "language").text = "en"

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"LanFi {args.version}"
    ET.SubElement(item, "pubDate").text = dt.datetime.now(dt.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )
    ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}version").text = args.build
    ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString").text = args.version
    ET.SubElement(
        item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}minimumSystemVersion"
    ).text = args.minimum_system
    ET.SubElement(item, "description").text = notes
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            "length": args.length,
            "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature": args.signature,
            "type": "application/octet-stream",
        },
    )

    ET.indent(rss, space="  ")
    pathlib.Path(args.output).write_bytes(ET.tostring(rss, encoding="utf-8", xml_declaration=True))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
