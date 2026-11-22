import AppKit
import Darwin
import Foundation
import LanFiCore
import Network
import UniformTypeIdentifiers

/// P3.6 — attributes host names to the apps that contacted them.
///
/// Sources, in order: an IP → host index built from HAR archives the user
/// opened in LanFi (only `serverIPAddress` and `host`), then cached reverse DNS
/// of the remote endpoints in `lsof`. Payload, paths, query strings, cookies
/// and URLs are never read or stored. LanFi's own process is excluded.
@MainActor
final class DomainAttributionModel: ObservableObject {
    static let shared = DomainAttributionModel()
    static let sampleInterval: TimeInterval = 300

    @Published private(set) var attribution: AppDomainAttribution = .empty
    @Published private(set) var isSampling = false
    @Published private(set) var lastSampleAt: Date?

    private var timer: Timer?
    private var isSampleInFlight = false
    private var httpIndex: [String: String] = [:]
    private var reverseCache: [String: String?] = [:]
    private let fileURL: URL
    private let indexURL: URL

    init(
        fileURL: URL = DomainAttributionModel.defaultFileURL,
        indexURL: URL = DomainAttributionModel.defaultIndexURL
    ) {
        self.fileURL = fileURL
        self.indexURL = indexURL
    }

    nonisolated static var defaultFileURL: URL {
        supportDirectory.appendingPathComponent("app-domains.json")
    }

    nonisolated static var defaultIndexURL: URL {
        supportDirectory.appendingPathComponent("http-domain-index.json")
    }

    nonisolated private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKey.processTrafficEnabled.rawValue)
    }

    func start() {
        guard timer == nil else { return }
        load()
        Task { await sampleNow() }
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sampleNow() }
        }
        timer.tolerance = Self.sampleInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Merges the IP → host hints from a user-opened HAR. Only host names are
    /// kept; the archive itself is never copied into Application Support.
    func recordHTTPCapture(_ traffic: HARTraffic) {
        let index = DomainAttributionRules.httpDomainIndex(from: traffic)
        guard !index.isEmpty else { return }
        for (ip, domain) in index {
            httpIndex[ip] = domain
        }
        saveIndex()
    }

    func sampleNow() async {
        guard isEnabled, !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampleInFlight = false
            isSampling = false
        }
        do {
            let connections = try await OpenConnectionsService.fetch(includeListeners: false)
            var addressesByApp: [String: Set<String>] = [:]
            for connection in connections {
                guard
                    !DomainAttributionRules.isOwnProcess(
                        connection.process, pid: connection.pid),
                    let address = DomainAttributionRules.remoteAddress(connection.remote)
                else { continue }
                addressesByApp[connection.process, default: []].insert(address)
            }
            for (app, addresses) in addressesByApp {
                for address in addresses {
                    guard let domain = await domain(for: address) else { continue }
                    attribution.record(app: app, domain: domain)
                }
            }
            if let cutoff = Calendar.current.date(
                byAdding: .day, value: -AppDomainAttribution.retentionDays, to: Date())
            {
                attribution.prune(before: cutoff)
            }
            lastSampleAt = Date()
            save()
        } catch {
            // lsof can be missing or restricted; the next tick retries and the
            // screen simply keeps the last attribution it had.
        }
    }

    func reset() {
        attribution = .empty
        save()
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LanFi-app-domains.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? attribution.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Resolution

    func domain(for address: String) async -> String? {
        if let cached = reverseCache[address] { return cached }
        if let known = httpIndex[address], let domain = DomainAttributionRules.normalize(known) {
            reverseCache[address] = domain
            return domain
        }
        let resolved = await Task.detached(priority: .utility) {
            Self.reverseDNS(address)
        }.value
        let domain = resolved.flatMap(DomainAttributionRules.normalize)
        reverseCache[address] = domain
        return domain
    }

    nonisolated static func reverseDNS(_ address: String) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result: Int32
        if IPv4Address(address) != nil {
            var socketAddress = sockaddr_in()
            socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            socketAddress.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, address, &socketAddress.sin_addr) == 1 else {
                return nil
            }
            result = withUnsafePointer(to: &socketAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    getnameinfo(
                        address, socklen_t(MemoryLayout<sockaddr_in>.size),
                        &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
        } else if IPv6Address(address) != nil {
            var socketAddress = sockaddr_in6()
            socketAddress.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            socketAddress.sin6_family = sa_family_t(AF_INET6)
            guard inet_pton(AF_INET6, address, &socketAddress.sin6_addr) == 1 else {
                return nil
            }
            result = withUnsafePointer(to: &socketAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    getnameinfo(
                        address, socklen_t(MemoryLayout<sockaddr_in6>.size),
                        &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
        } else {
            return nil
        }
        guard result == 0 else { return nil }
        return String(cString: host)
    }

    // MARK: - Persistence

    func load() {
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            attribution = (try? decoder.decode(AppDomainAttribution.self, from: data)) ?? .empty
        }
        if let data = try? Data(contentsOf: indexURL) {
            httpIndex = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
    }

    private func save() {
        saveValue(attribution, to: fileURL)
    }

    private func saveIndex() {
        saveValue(httpIndex, to: indexURL)
    }

    private func saveValue<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
