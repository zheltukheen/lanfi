import Foundation

extension MCPToolkit {
    // MARK: - Probes

    static func ping(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let count = max(1, min(int(arguments, "count") ?? 4, 100))
            let timeout = max(0.2, min(double(arguments, "timeout") ?? 1.5, 10))
            let useTCP = (string(arguments, "transport") ?? "icmp").lowercased() == "tcp"
            let port = UInt16(clamping: max(1, min(int(arguments, "port") ?? 443, 65_535)))
            let probe: any PingProbing =
                useTCP ? TCPPingProbe(port: port) : ICMPPingProbe()
            let service = PingService(probe: probe)
            var samples: [PingSample] = []
            for await sample in service.stream(host: host, count: count, interval: 0.25) {
                samples.append(sample)
            }
            guard !samples.isEmpty else { return .error("No probes were sent.") }
            let stats = PingStatistics(host: host, samples: samples)
            return .json([
                "host": stats.host,
                "transmitted": stats.transmitted,
                "received": stats.received,
                "packetLossPercent": stats.packetLossPercent,
                "minMs": stats.minMilliseconds as Any,
                "averageMs": stats.averageMilliseconds as Any,
                "maxMs": stats.maxMilliseconds as Any,
                "jitterMs": stats.jitterMilliseconds as Any,
                "samples": samples.map {
                    [
                        "sequence": $0.sequence,
                        "ms": $0.rttMilliseconds as Any,
                        "error": $0.error as Any,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func traceroute(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let maxHops = max(1, min(int(arguments, "maxHops") ?? 20, 64))
            let wait = max(1, min(int(arguments, "waitSeconds") ?? 2, 10))
            let report = try await SystemTracerouteRunner().trace(
                host: host, maxHops: maxHops, waitSeconds: wait,
                resolveNames: flag(arguments, "resolveNames"))
            return .json([
                "host": report.host,
                "reachedTarget": report.reachedTarget,
                "hops": report.hops.map {
                    [
                        "ttl": $0.ttl,
                        "address": $0.address as Any,
                        "hostname": $0.hostname as Any,
                        "ms": $0.milliseconds,
                        "timedOut": $0.timedOut,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func mtr(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let rounds = max(1, min(int(arguments, "rounds") ?? 5, 30))
            let hops = max(1, min(int(arguments, "maxHops") ?? 15, 40))
            let report = try await MTRService(runner: SystemTracerouteRunner()).run(
                host: host, rounds: rounds, maxHops: hops, waitSeconds: 1,
                onUpdate: { _ in })
            let hopRows: [[String: Any]] = report.hops.map { hop in
                var row: [String: Any] = [
                    "hop": hop.hop,
                    "sent": hop.sent,
                    "received": hop.received,
                ]
                row["address"] = hop.address as Any
                row["hostname"] = hop.hostname as Any
                row["lossPercent"] =
                    hop.sent == 0
                    ? 0 : Double(hop.sent - hop.received) / Double(hop.sent) * 100
                row["lastMs"] = hop.lastMilliseconds as Any
                row["averageMs"] = hop.averageMilliseconds as Any
                row["jitterMs"] = hop.jitterMilliseconds as Any
                return row
            }
            return .json(["host": report.host, "rounds": report.rounds, "hops": hopRows])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func portScan(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let spec = ports(arguments, fallback: "22,80,443,8080")
            guard !spec.isEmpty else { return .error("No ports to scan.") }
            let timeout = max(0.2, min(double(arguments, "timeout") ?? 1.0, 10))
            let results = await PortScanner(probe: TCPPortProbe()).scan(
                host: host, ports: spec, timeout: timeout, concurrency: 24)
            return .json([
                "host": host,
                "open": results.filter { $0.state == .open }.count,
                "results": results.map {
                    [
                        "port": Int($0.port),
                        "state": $0.state.rawValue,
                        "service": $0.service as Any,
                        "ms": $0.responseMilliseconds as Any,
                        "detail": $0.detail as Any,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func pathCheck(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let spec = ports(arguments, fallback: "80,443")
            guard !spec.isEmpty else { return .error("No ports to check.") }
            let results = await withTaskGroup(of: [String: Any].self) { group in
                for port in spec.prefix(32) {
                    group.addTask {
                        let outcome = await TCPProbe.connect(host: host, port: port, timeout: 4)
                        var row: [String: Any] = ["port": Int(port)]
                        switch outcome {
                        case .open(let milliseconds):
                            row["state"] = "open"
                            row["ms"] = milliseconds
                        case .closed(let milliseconds, let detail):
                            row["state"] = "closed"
                            row["ms"] = milliseconds as Any
                            row["detail"] = detail as Any
                        case .filtered(let detail):
                            row["state"] = "filtered"
                            row["detail"] = detail as Any
                        }
                        return row
                    }
                }
                var rows: [[String: Any]] = []
                for await row in group { rows.append(row) }
                return rows.sorted {
                    ($0["port"] as? Int ?? 0) < ($1["port"] as? Int ?? 0)
                }
            }
            return .json(["host": host, "results": results])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func dnsLookup(_ arguments: [String: Any]) async -> MCPToolOutcome {
        guard let name = string(arguments, "name") else {
            return .error("Pass a domain as `name`.")
        }
        guard let type = recordType(string(arguments, "type") ?? "A") else {
            return .error("Unsupported record type.")
        }
        let resolverArgument = (string(arguments, "resolver") ?? "system").lowercased()
        let resolver: DNSResolver
        switch resolverArgument {
        case "cloudflare": resolver = .cloudflare
        case "google": resolver = .google
        case "system": resolver = .system
        default:
            guard let custom = DNSResolver.custom(resolverArgument) else {
                return .error("Unsupported resolver: \(resolverArgument).")
            }
            resolver = custom
        }
        do {
            let result = try await UDPDNSClient().lookup(
                host: name, type: type, resolver: resolver, timeout: 6)
            return .json([
                "host": result.host,
                "resolver": result.resolver,
                "milliseconds": result.milliseconds,
                "records": result.records.map(recordJSON),
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func dnsPropagation(_ arguments: [String: Any]) async -> MCPToolOutcome {
        guard let name = string(arguments, "name") else {
            return .error("Pass a domain as `name`.")
        }
        guard let type = recordType(string(arguments, "type") ?? "A") else {
            return .error("Unsupported record type.")
        }
        let resolvers = DNSResolver.propagation
        let rows = await withTaskGroup(of: [String: Any].self) { group in
            for resolver in resolvers {
                group.addTask {
                    do {
                        let result = try await UDPDNSClient().lookup(
                            host: name, type: type, resolver: resolver, timeout: 5)
                        return [
                            "resolver": resolver.name,
                            "address": resolver.address ?? "system",
                            "ms": result.milliseconds,
                            "records": result.records.map { $0.value },
                            "error": NSNull(),
                        ]
                    } catch {
                        return [
                            "resolver": resolver.name,
                            "address": resolver.address ?? "system",
                            "ms": 0,
                            "records": [String](),
                            "error": error.localizedDescription,
                        ]
                    }
                }
            }
            var values: [[String: Any]] = []
            for await value in group { values.append(value) }
            return values
        }
        return .json(["name": name, "type": type.label, "results": rows])
    }

    static func whois(_ arguments: [String: Any]) async -> MCPToolOutcome {
        guard let query = string(arguments, "query") else {
            return .error("Pass a domain or IP as `query`.")
        }
        do {
            let report = try await WhoisClient().lookup(query)
            return .json([
                "query": report.query,
                "objectType": report.objectType,
                "name": report.name,
                "handle": report.handle as Any,
                "registrar": report.registrar as Any,
                "statuses": report.statuses,
                "nameservers": report.nameservers,
                "events": report.events.map {
                    [
                        "action": $0.action,
                        "date": $0.date.map {
                            ISO8601DateFormatter().string(from: $0) as Any
                        } ?? NSNull(),
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func geoIP(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let report = try await GeoIPClient().lookup(string(arguments, "query"))
            return .json([
                "query": report.query,
                "ip": report.ip,
                "type": report.type,
                "country": report.country,
                "countryCode": report.countryCode,
                "region": report.region,
                "city": report.city,
                "latitude": report.latitude,
                "longitude": report.longitude,
                "asn": report.asn as Any,
                "organization": report.organization,
                "isp": report.isp,
                "timezone": report.timezone,
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func tls(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let port = UInt16(clamping: max(1, min(int(arguments, "port") ?? 443, 65_535)))
            let report = try await URLSessionTLSCertificateInspector().inspect(
                host: host, port: port, timeout: 8)
            return .json([
                "host": report.host,
                "port": Int(report.port),
                "trusted": report.trusted,
                "expired": report.expired,
                "expiresSoon": report.expiresSoon,
                "daysRemaining": report.daysRemaining as Any,
                "certificates": report.certificates.map {
                    [
                        "subject": $0.subject,
                        "issuer": $0.issuer,
                        "notBefore": $0.notBefore.map {
                            ISO8601DateFormatter().string(from: $0) as Any
                        } ?? NSNull(),
                        "notAfter": $0.notAfter.map {
                            ISO8601DateFormatter().string(from: $0) as Any
                        } ?? NSNull(),
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func subnet(_ arguments: [String: Any]) -> MCPToolOutcome {
        guard let input = string(arguments, "input") else {
            return .error("Pass a CIDR or address plus mask as `input`.")
        }
        guard let info = SubnetCalculator.parse(input) else {
            return .error("Could not parse the IPv4 network.")
        }
        return .json([
            "network": info.network.description,
            "broadcast": info.broadcast.description,
            "netmask": info.netmask.description,
            "prefixLength": info.prefixLength,
            "firstUsable": info.firstUsable?.description as Any,
            "lastUsable": info.lastUsable?.description as Any,
            "totalAddresses": info.totalAddresses,
            "usableHosts": info.usableHosts,
        ])
    }

    static func interfaces() -> MCPToolOutcome {
        let report = SystemInterfaceScanner.scan()
        return .json([
            "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
            "primaryInterface": report.primaryInterface as Any,
            "router": report.router as Any,
            "dnsServers": report.dnsServers,
            "interfaces": report.interfaces.map {
                [
                    "name": $0.bsdName,
                    "displayName": $0.displayName,
                    "kind": $0.kind.rawValue,
                    "up": $0.isUp,
                    "running": $0.isRunning,
                    "primary": $0.isPrimary,
                    "mac": $0.macAddress as Any,
                    "ipv4": $0.ipv4.map(\.address),
                    "ipv6": $0.ipv6.map(\.address),
                    "ssid": $0.ssid as Any,
                    "rssi": $0.rssi as Any,
                    "rxBytes": $0.rxBytes,
                    "txBytes": $0.txBytes,
                ] as [String: Any]
            },
        ])
    }

    static func routes() async -> MCPToolOutcome {
        do {
            let routes = try await RouteTableReader().read()
            return .json([
                "routes": routes.map {
                    [
                        "destination": $0.destination,
                        "gateway": $0.gateway,
                        "flags": $0.flags,
                        "interface": $0.interface,
                        "isDefault": $0.isDefault,
                    ] as [String: Any]
                }
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func lanScan(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let service = LANScannerService(
                probePorts: ports(arguments, fallback: "22,80,443,445,5000,7000,8080,3389"))
            let result = try await service.scan(knownMACs: [], guardEnabled: false)
            return .json([
                "interface": result.interfaceName,
                "subnet": result.subnet,
                "gateway": result.gateway as Any,
                "devices": result.devices.map {
                    [
                        "ip": $0.ip,
                        "mac": $0.mac as Any,
                        "vendor": $0.vendor as Any,
                        "hostname": $0.hostname as Any,
                        "model": $0.model as Any,
                        "manufacturer": $0.manufacturer as Any,
                        "version": $0.version as Any,
                        "role": $0.deviceType as Any,
                        "services": $0.services,
                        "banners": Dictionary(
                            uniqueKeysWithValues: $0.banners.map { (String($0.key), $0.value) }),
                        "openPorts": $0.openPorts.map(Int.init),
                        "latencyMs": $0.latencyMilliseconds as Any,
                        "isGateway": $0.isGateway,
                        "isThisMac": $0.isThisMac,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
