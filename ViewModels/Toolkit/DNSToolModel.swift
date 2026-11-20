import Foundation
import SwiftUI

// MARK: - DNS

@MainActor
final class DNSToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var tab: DNSLookupTab = .records
    @Published var type: DNSRecordType = .a
    @Published var resolverChoice = "cloudflare"
    @Published var customResolver = "1.1.1.1"
    @Published private(set) var result: DNSLookupResult?
    @Published private(set) var mailReport: DNSMailReport?
    @Published private(set) var isRunning = false
    @Published private(set) var comparison: DNSComparison?
    @Published private(set) var isComparing = false
    @Published var errorMessage: String?
    /// Country and network per resolved A/AAAA address, filled after the answer
    /// arrives so a slow lookup never delays the records themselves.
    @Published private(set) var annotations: [String: DNSAddressAnnotation] = [:]
    /// Short lines under the answers that explain their shape.
    @Published private(set) var notes: [DNSAnswerNote] = []

    private var task: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?
    private var comparisonTask: Task<Void, Never>?

    var resolver: DNSResolver {
        switch resolverChoice {
        case "system": return .system
        case "google": return .google
        case "custom":
            return DNSResolver.custom(customResolver) ?? .system
        default: return .cloudflare
        }
    }

    func run() {
        AnalysisTarget.shared.remember(host)
        switch tab {
        case .records: runRecords()
        case .mail, .reports: runMail()
        }
    }

    private func runRecords() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        if resolverChoice == "custom", DNSResolver.custom(customResolver) == nil {
            errorMessage = "Enter a resolver address, for example 1.1.1.1."
            return
        }
        errorMessage = nil
        result = nil
        annotations = [:]
        notes = []
        enrichTask?.cancel()
        isRunning = true
        let selectedType = type
        let selectedResolver = resolver
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let lookup = try await UDPDNSClient().lookup(
                    host: target.host, type: selectedType, resolver: selectedResolver)
                self.result = lookup
                self.annotate(lookup, type: selectedType, resolver: selectedResolver)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    /// Annotates the resolved addresses with country and network. Runs apart
    /// from the lookup so the table appears immediately.
    private func annotate(
        _ lookup: DNSLookupResult, type: DNSRecordType, resolver: DNSResolver
    ) {
        notes = []
        guard type == .a || type == .aaaa else { return }
        enrichTask?.cancel()
        let host = lookup.host
        enrichTask = Task { [weak self] in
            async let annotations = DNSAddressEnricher().annotations(for: lookup.records)
            async let systemRecords = Self.systemAnswer(
                host: host, type: type, askedResolver: resolver)
            let (filled, system) = await (annotations, systemRecords)
            guard let self, !Task.isCancelled else { return }
            self.annotations = filled
            self.notes = DNSAnswerExplanation.notes(
                records: lookup.records, systemRecords: system,
                organizations: filled.values.map(\.organization))
            self.enrichTask = nil
        }
    }

    /// Asks the system resolver the same question, unless that is what the
    /// user already used. A failure here is silence, not an error row: the
    /// answer above is still valid.
    private static func systemAnswer(
        host: String, type: DNSRecordType, askedResolver: DNSResolver
    ) async -> [DNSRecord]? {
        guard askedResolver.id != DNSResolver.system.id else { return nil }
        return try? await UDPDNSClient().lookup(
            host: host, type: type, resolver: .system, timeout: 3
        ).records
    }

    private func runMail() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        if resolverChoice == "custom", DNSResolver.custom(customResolver) == nil {
            errorMessage = "Enter a resolver address, for example 1.1.1.1."
            return
        }
        errorMessage = nil
        mailReport = nil
        isRunning = true
        let selectedResolver = resolver
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.task = nil
            }
            let report = await DNSMailLookupService().lookup(
                domain: target.host, resolver: selectedResolver)
            if Task.isCancelled { return }
            self.mailReport = report
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        enrichTask?.cancel()
        enrichTask = nil
        annotations = [:]
        notes = []
        comparisonTask?.cancel()
        comparisonTask = nil
        result = nil
        mailReport = nil
        comparison = nil
        errorMessage = nil
        isRunning = false
        isComparing = false
    }

    /// Sends the current name and type to every built-in resolver over UDP and
    /// DoH and reports whether the answers agree.
    func compare() {
        guard !isComparing else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        errorMessage = nil
        comparison = nil
        isComparing = true
        let selectedType = type
        comparisonTask = Task { [weak self] in
            let report = await DNSComparisonService().compare(
                host: target.host, type: selectedType)
            guard let self else { return }
            if Task.isCancelled { return }
            self.comparison = report
            self.isComparing = false
            self.comparisonTask = nil
        }
    }
}
