# MCP server for AI agents

`lanfi-cli mcp` runs a [Model Context Protocol](https://modelcontextprotocol.io)
server over stdio. Agents can read the scan LanFi collected, run the same
analysis the app renders, and execute the toolkit's probes (ping, port scan,
DNS, TLS, WHOIS, LAN discovery, iperf3 and more).

The scan tools do not scan Wi-Fi themselves. They read:

- the live snapshot the app writes to
  `~/Library/Application Support/LanFi/mcp/latest-scan.json` (refreshed at most
  every 5 seconds while LanFi runs), or
- any scan JSON exported from LanFi (`Data → Export JSON…`), passed as `path`.

Probe tools run locally on this Mac and never require the app.

## Build

```bash
xcodegen generate
xcodebuild build -project LanFi.xcodeproj -scheme lanfi-cli \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -configuration Release
# binary: ~/Library/Developer/Xcode/DerivedData/LanFi-*/Build/Products/Release/lanfi-cli
```

## Register the server

The installed app serves MCP itself, so no extra binary is needed:

```bash
claude mcp add lanfi -- /Applications/LanFi.app/Contents/MacOS/LanFi --mcp
```

`--mcp` runs headless on stdio: no window, no menu-bar item, no scan of its
own. The same works for a build from this repository, e.g.
`./build/LanFi-Universal/LanFi.app/Contents/MacOS/LanFi --mcp`, and the CLI
below stays available for scripted use.

Claude Code / Claude Desktop, Cursor and other MCP clients take the same
`command` + `args` pair. Use the absolute path to the app or CLI binary.

```json
{
  "mcpServers": {
    "lanfi": {
      "command": "/absolute/path/to/lanfi-cli",
      "args": ["mcp"]
    }
  }
}
```

## Tools

### Scan analysis

| Tool | Purpose |
| --- | --- |
| `lanfi_scan_summary` | SSID, BSSID, band, channel, signal and security per network. |
| `lanfi_analyze` | Quality score/grade, issues, channel recommendations, security findings. |
| `lanfi_protocols` | Radio, EHT/MLO, security, spectrum, mobility, format and vendor blocks with warnings. Optional `ssid`/`bssid`. |
| `lanfi_channels` | Occupancy per channel and ranked recommendations for 2.4/5/6 GHz. |
| `lanfi_capture` | Parse a pcap/pcapng capture: beacons and assembled MLO groups. |
| `lanfi_har` | Analyse a HAR archive: slowest requests, failures, p95 latency, bytes per host and the dominant timing phase (credential values redacted by default). |
| `lanfi_spectrum` | Analyse a hardware spectrum CSV (RF Explorer, Wi-Spy/Chanalyzer): span, noise floor, peak, per-band strongest signal and time above -70/-60/-50 dBm. |
| `lanfi_client_analytics` | Per-access-point advertised client load from the latest scan: clients, utilization, busiest APs and plain-language insights. |
| `lanfi_survey_plan` | Plan access-point placement for a rectangular floor: free-space radius, grid layout, spacing and estimated coverage. |

### Network probes

| Tool | Purpose |
| --- | --- |
| `lanfi_ping` | ICMP or TCP ping with loss, jitter and per-probe RTT. |
| `lanfi_traceroute` | System traceroute with per-hop addresses and timings. |
| `lanfi_mtr` | Multi-round per-hop loss and jitter. |
| `lanfi_port_scan` | TCP connect scan of a host and port list. |
| `lanfi_path_check` | TCP reachability of a host on a few ports. |
| `lanfi_dns` | Resolve against the system, Cloudflare, Google or a custom resolver. |
| `lanfi_dns_propagation` | Query the public resolver set and group answers. |
| `lanfi_whois` | Domain or IP registration data. |
| `lanfi_geoip` | City, country, ASN and provider for an address. |
| `lanfi_tls` | Certificate chain, trust and expiry for a host:port. |
| `lanfi_subnet` | IPv4 subnet calculator. |
| `lanfi_interfaces` | This Mac's interfaces, primary route and DNS. |
| `lanfi_routes` | The IPv4 routing table. |
| `lanfi_lan_scan` | ARP, Bonjour and TCP sweep of the local subnet. |
| `lanfi_iperf3` | Run the iperf3 client against your own server. |
| `lanfi_speed_test` | Apple networkQuality throughput and bufferbloat. |
| `lanfi_open_connections` | TCP connections on this Mac from read-only `lsof`: process, PID, user, protocol, endpoints and state. |

### Device Shelf

`lanfi_devices` reads the inventory the LAN Scanner builds. It is stored
locally at `~/Library/Application Support/LanFi/device-shelf.json`; no account,
cloud or network call is involved.

| Argument | Meaning |
| --- | --- |
| `online` | Only devices that answered in the latest scan. |
| `favourite` | Only starred devices. |
| `risky` | Only devices with at least one medium-or-higher risk finding. |
| `search` | Case-insensitive match on name, hostname, IP, MAC, vendor or type. |
| `limit` | Maximum rows, default 200, capped at 1000. |
| `directory` | Folder holding `device-shelf.json`; omit for the app's shelf. |

Each row carries `name`, `alias`-resolved `displayName`, `ip`, `mac`,
`hostname`, `vendor`, `category`, `online`, `openPorts`, `availabilityPercent`,
`latencyMs`, `riskScore`, `checks`, `firstSeen`, `lastSeen` and a `findings`
array (`port`, `title`, `severity`, `advice`). The response also reports
`shelfPath`, the total `count` and how many rows were `returned`.

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lanfi_devices","arguments":{"risky":true}}}' \
  | lanfi-cli mcp
```

### Client analytics, survey planning and open connections

These three tools need no live app session per call:

- `lanfi_client_analytics` reads the live snapshot (or an exported scan JSON),
  the same way `lanfi_scan_summary` does;
- `lanfi_survey_plan` is a pure calculator over the dimensions you pass;
- `lanfi_open_connections` runs `/usr/sbin/lsof -nP -iTCP` read-only. It is
  never elevated, so sockets owned by other users can be hidden.

| Argument | Tool | Meaning |
| --- | --- | --- |
| `path` | `lanfi_client_analytics` | Scan JSON export path; omit for the live snapshot. |
| `widthMeters` | `lanfi_survey_plan` | Floor width in metres, default 20. |
| `heightMeters` | `lanfi_survey_plan` | Floor height in metres, default 12. |
| `targetRSSI` | `lanfi_survey_plan` | Design target in dBm, default -65. |
| `txPowerDbm` | `lanfi_survey_plan` | Access-point transmit power, default 20 dBm. |
| `band` | `lanfi_survey_plan` | `2.4GHz`, `5GHz` or `6GHz`, default `5GHz`. |
| `channel` | `lanfi_survey_plan` | Channel used for the path-loss assumption, default 36. |
| `listeners` | `lanfi_open_connections` | Include listening sockets, default false. |
| `limit` | `lanfi_open_connections` | Maximum connection rows, default 500, capped at 2000. |

`lanfi_client_analytics` returns `advertisedClients`, `accessPoints`,
`reportingAccessPoints`, `idleAccessPoints`, an `accessPointLoad` array
(`bssid`, `ssid`, `band`, `channel`, `clients`, `utilizationPercent`, `rssi`)
and `insights`. The client count is what the beacon advertises, not a
per-client measurement: macOS exposes no client list to Wi-Fi scan APIs.

`lanfi_survey_plan` returns `accessPointCount`, `radiusMeters`,
`spacingMeters`, `estimatedCoveragePercent`, the `accessPoints` grid (`x`, `y`
in metres) and `notes` about the assumptions it made.

`lanfi_open_connections` returns `count`, `returned`, a `processes` summary
(`process`, `connections`) and the `connections` rows (`process`, `pid`,
`user`, `protocol`, `local`, `remote`, `state`).

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lanfi_client_analytics","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lanfi_survey_plan","arguments":{"widthMeters":24,"heightMeters":14,"targetRSSI":-67,"band":"6GHz"}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lanfi_open_connections","arguments":{"listeners":true,"limit":50}}}' \
  | lanfi-cli mcp
```

### Live actions

These tools do not read a file: they ask the **running app** to act. They are
off by default. Enable **Settings → MCP → “Allow MCP clients to act on the
running app”**, then keep LanFi open; the CLI writes a request into
`~/Library/Application Support/LanFi/mcp/live/`, the app executes it on its own
view models and writes the response back. Nothing listens on a port.

| Tool | Arguments | Effect |
| --- | --- | --- |
| `lanfi_scan_now` | — | Runs a Wi-Fi scan in the app and returns the network count. |
| `lanfi_start_capture` | `duration` (5–120 s), `interface`, `monitor`, `filter` | Runs one bounded `tcpdump` capture; macOS asks for administrator authorization. Returns the pcap path. |
| `lanfi_survey_sample` | — | Tags the newest Site Survey sample with the Mac's current location. Needs an active survey and Location permission. |

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lanfi_scan_now","arguments":{}}}' \
  | lanfi-cli mcp
```

If live actions are disabled or the app is not running, the tool returns
`isError: true` with the reason after a short timeout. Responses older than ten
minutes are pruned automatically.

### App state

| Tool | Purpose |
| --- | --- |
| `lanfi_uptime` | Uptime Monitor targets and their last checks. |
| `lanfi_diagnostics` | The most recent Internet Check report. |
| `lanfi_info` | Snapshot path, freshness and usage notes. |

Every tool returns JSON as its text content. Errors come back with
`isError: true` and a human-readable message.

## Testability

`MCPProtocol.handle(_:)` is transport-free and returns a JSON-RPC response (or
`nil` for notifications), so the whole server is unit tested without a client
or network. `MCPToolkit` owns the tool catalogue and dispatcher.
`Tests/MCPProtocolTests.swift` covers the handshake, the full catalogue, the
scan tools against a fixture, argument validation and the subnet tool.

```bash
xcodebuild test -project LanFi.xcodeproj -scheme LanFi \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Smoke test

The server speaks newline-delimited JSON-RPC on stdin:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lanfi_subnet","arguments":{"input":"192.168.1.10/24"}}}' \
  | ./lanfi-cli mcp
```
