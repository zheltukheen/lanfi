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
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

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
        isRunning = true
        let selectedType = type
        let selectedResolver = resolver
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let lookup = try await UDPDNSClient().lookup(
                    host: target.host, type: selectedType, resolver: selectedResolver)
                self.result = lookup
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
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
        result = nil
        mailReport = nil
        errorMessage = nil
        isRunning = false
    }
}
