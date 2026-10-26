# Vendor data

`Resources/oui` maps MAC address blocks to vendors. It contains **58,407
prefixes** with 24-bit (IEEE MA-L), 28-bit (MA-M) and 36-bit (MA-S) assignments.
Lookup uses the longest matching prefix (`Utils/OUIParser.swift`).

## Sources

- IEEE registration authority CSV exports:
  <https://standards-oui.ieee.org/oui/oui.csv>,
  <https://standards-oui.ieee.org/oui28/mam.csv>,
  <https://standards-oui.ieee.org/oui36/oui36.csv>
- Wireshark manufacturer registry:
  <https://www.wireshark.org/download/automated/data/manuf>

The generated file is tab-separated: `<6/7/9 hex prefix>\t<vendor>`. Entries
without a real organization (`Private`, `IEEE Registration Authority`) are
dropped; specific IEEE sub-allocations still resolve through longest-prefix
matching.

Wireshark is distributed under GPL-2.0; its `manuf` file is generated registry
data and is included here as a factual vendor registry with attribution. IEEE
registration data is published by the IEEE registration authority. Review the
upstream terms if you redistribute this database separately from LanFi.

## Refresh

```bash
python3 scripts/update_oui.py                 # download all sources
python3 scripts/update_oui.py local.csv        # one or more local files
OUI_OUTPUT=/tmp/oui python3 scripts/update_oui.py
```

The script refuses to overwrite the database with fewer than 30,000 prefixes,
so a failed download cannot silently empty the app's vendor list. Commit the
regenerated `Resources/oui` after reviewing the counts.
