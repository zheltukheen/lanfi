import Foundation
import SwiftUI

// MARK: - DNS propagation

@MainActor
final class DNSPropagationToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var type: DNSRecordType = .a
    @Published var expected = ""
    @Published private(set) var results: [DNSPropagationResult] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var summary: DNSPropagationSummary {
        DNSPropagationSummary(expected: expected, results: results)
    }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        errorMessage = nil
        results = []
        isRunning = true
        let selectedType = type
        let resolvers = DNSResolver.propagation
        task = Task { [weak self] in
            guard let self else { return }
            let collected = await withTaskGroup(of: DNSPropagationResult.self) { group in
                for resolver in resolvers {
                    group.addTask {
                        do {
                            let lookup = try await UDPDNSClient().lookup(
                                host: target.host,
                                type: selectedType,
                                resolver: resolver,
                                timeout: 4
                            )
                            return DNSPropagationResult(
                                resolver: resolver,
                                records: lookup.records,
                                milliseconds: lookup.milliseconds,
                                error: nil
                            )
                        } catch {
                            return DNSPropagationResult(
                                resolver: resolver,
                                records: [],
                                milliseconds: 0,
                                error: error.localizedDescription
                            )
                        }
                    }
                }
                var values: [DNSPropagationResult] = []
                for await result in group { values.append(result) }
                return values
            }
            if Task.isCancelled { return }
            let order = Dictionary(
                uniqueKeysWithValues: resolvers.enumerated().map { ($1.id, $0) })
            self.results = collected.sorted {
                order[$0.resolver.id, default: 99] < order[$1.resolver.id, default: 99]
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        results = []
        errorMessage = nil
    }
}
