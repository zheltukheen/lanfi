import Foundation
import LanFiCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// P3.10 — resolves a plain-language description for a domain or a process.
///
/// The bundled catalog always answers first and works offline. Unknown names
/// stay "Unknown service" unless the user opts into the on-device model, which
/// runs locally on macOS 26 and later; nothing is uploaded and generated text
/// is cached in memory only.
@MainActor
final class ServiceDescriptionResolver: ObservableObject {
    static let shared = ServiceDescriptionResolver()

    @Published private(set) var generated: [String: ServiceDescription] = [:]
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var lastError: String?

    /// Apple Intelligence must be supported, enabled and finished downloading.
    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return SystemLanguageModel.default.isAvailable
            }
        #endif
        return false
    }

    var isEnabled: Bool {
        AppSettingsStore.shared.settings.automation.serviceDescriptions
    }

    func description(forDomain raw: String) -> ServiceDescription {
        let host = ServiceDescriptionCatalog.normalizedHost(raw)
        if let bundled = ServiceDescriptionCatalog.describe(domain: host) { return bundled }
        return generated[host] ?? .unknownService
    }

    func description(forProcess raw: String) -> ServiceDescription {
        if let bundled = ServiceDescriptionCatalog.describe(process: raw) { return bundled }
        return generated[raw.trimmingCharacters(in: .whitespaces).lowercased()] ?? .unknownService
    }

    /// Only unknown names, only when the model is available and enabled.
    func canGenerate(domain raw: String) -> Bool {
        let host = ServiceDescriptionCatalog.normalizedHost(raw)
        return isEnabled && Self.isModelAvailable && !host.isEmpty
            && ServiceDescriptionCatalog.describe(domain: host) == nil
            && generated[host] == nil && !pending.contains(host)
    }

    func generate(domain raw: String) async {
        let host = ServiceDescriptionCatalog.normalizedHost(raw)
        guard canGenerate(domain: host) else { return }
        let subject = String(host.prefix(80))
        await generate(
            key: host,
            prompt:
                "A Mac on a home network connects to the domain \"\(subject)\". In one short sentence of at most 12 words, say which service or company this domain belongs to and what it is for. No quotes, no preamble."
        )
    }

    // MARK: - Model

    private func generate(key: String, prompt: String) async {
        pending.insert(key)
        defer { pending.remove(key) }
        lastError = nil

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                guard SystemLanguageModel.default.isAvailable else {
                    lastError = String(
                        localized: "The on-device model is not available. Check Apple Intelligence in System Settings."
                    )
                    return
                }
                do {
                    let session = LanguageModelSession(
                        instructions:
                            "You label network traffic. Answer with a short service description only.")
                    let response = try await session.respond(to: prompt)
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    generated[key] = ServiceDescription(
                        title: String(text.prefix(160)),
                        category: String(localized: "On-device model"),
                        source: .onDeviceModel)
                } catch {
                    lastError = error.localizedDescription
                }
                return
            }
        #endif

        lastError = String(localized: "The on-device model needs macOS 26 or later.")
    }
}
