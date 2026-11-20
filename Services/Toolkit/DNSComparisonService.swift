import Foundation

/// Queries the same name and type through UDP and DoH resolvers in parallel and
/// reports whether the answers agree. A resolver that times out is reported as
/// a failed row rather than quietly dropped, because "one server answered" is
/// the result that matters when port 53 is being intercepted.
struct DNSComparisonService: Sendable {
    var udpClient: any DNSLookuping = UDPDNSClient()
    var dohClient: DoHDNSClient = DoHDNSClient()
    var dotClient: DoTDNSClient = DoTDNSClient()

    func compare(
        host: String,
        type: DNSRecordType,
        udpResolvers: [DNSResolver] = DNSResolver.builtIn,
        dohResolvers: [DoHResolver] = DoHResolver.builtIn,
        dotResolvers: [DoTResolver] = DoTResolver.builtIn
    ) async -> DNSComparison {
        await withTaskGroup(of: DNSComparisonEntry.self) { group in
            for resolver in udpResolvers {
                group.addTask {
                    let started = Date()
                    do {
                        let result = try await udpClient.lookup(
                            host: host, type: type, resolver: resolver, timeout: 4)
                        return DNSComparisonEntry(
                            id: "udp:\(resolver.id)", name: resolver.name, transport: .udp,
                            records: result.records, milliseconds: result.milliseconds,
                            failure: nil)
                    } catch {
                        return DNSComparisonEntry(
                            id: "udp:\(resolver.id)", name: resolver.name, transport: .udp,
                            records: [], milliseconds: Int(Date().timeIntervalSince(started) * 1000),
                            failure: error.localizedDescription)
                    }
                }
            }
            for resolver in dohResolvers {
                group.addTask {
                    let started = Date()
                    do {
                        let result = try await dohClient.lookup(
                            host: host, type: type, resolver: resolver, timeout: 6)
                        return DNSComparisonEntry(
                            id: "doh:\(resolver.id)", name: resolver.name, transport: .doh,
                            records: result.records, milliseconds: result.milliseconds,
                            failure: nil)
                    } catch {
                        return DNSComparisonEntry(
                            id: "doh:\(resolver.id)", name: resolver.name, transport: .doh,
                            records: [], milliseconds: Int(Date().timeIntervalSince(started) * 1000),
                            failure: error.localizedDescription)
                    }
                }
            }
            for resolver in dotResolvers {
                group.addTask {
                    let started = Date()
                    do {
                        let result = try await dotClient.lookup(
                            host: host, type: type, resolver: resolver, timeout: 6)
                        return DNSComparisonEntry(
                            id: "dot:\(resolver.id)", name: resolver.name, transport: .dot,
                            records: result.records, milliseconds: result.milliseconds,
                            failure: nil)
                    } catch {
                        return DNSComparisonEntry(
                            id: "dot:\(resolver.id)", name: resolver.name, transport: .dot,
                            records: [], milliseconds: Int(Date().timeIntervalSince(started) * 1000),
                            failure: error.localizedDescription)
                    }
                }
            }
            var entries: [DNSComparisonEntry] = []
            for await entry in group {
                entries.append(entry)
            }
            entries.sort { lhs, rhs in
                if lhs.transport != rhs.transport { return lhs.transport.rank < rhs.transport.rank }
                return lhs.name < rhs.name
            }
            return DNSComparison(host: host, type: type, entries: entries)
        }
    }
}
