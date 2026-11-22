import Foundation

/// Reads and changes the system resolver through `networksetup`. The change is
/// explicitly user-driven: the confirmation sheet shows the current and the
/// pending servers first, and the call below is the only place that asks for
/// administrator authorization.
struct DNSResolverSwitchService {
    enum SwitchError: LocalizedError, Equatable {
        case commandFailed(String)
        case authorizationCancelled
        case unsupportedOutput(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message): return message
            case .authorizationCancelled:
                return String(localized: "Authorization was cancelled; DNS was not changed.")
            case .unsupportedOutput(let message): return message
            }
        }
    }

    var backupURL: URL = DNSResolverSwitchService.defaultBackupURL

    static var defaultBackupURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("dns-switch-backup.json")
    }

    /// Enabled network services in the order `networksetup` lists them.
    func services() async throws -> [String] {
        let output = try await Self.run("/usr/sbin/networksetup", ["-listallnetworkservices"])
        let names = DNSResolverSwitch.services(from: output)
        guard !names.isEmpty else {
            throw SwitchError.unsupportedOutput(
                String(localized: "No network services were found."))
        }
        return names
    }

    func currentServers(service: String) async throws -> [String] {
        let output = try await Self.run(
            "/usr/sbin/networksetup", ["-getdnsservers", service])
        return DNSResolverSwitch.servers(from: output)
    }

    func backup() -> DNSResolverBackup? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DNSResolverBackup.self, from: data)
    }

    /// Applies the plan and flushes the cache. The previous servers are stored
    /// only after the command succeeded, so a cancelled prompt changes nothing.
    func apply(_ plan: DNSResolverPlan) async throws {
        let script = DNSResolverSwitch.authorizedScript(
            service: plan.service, servers: plan.newServers)
        try await Self.authorized(script)
        let backup = DNSResolverBackup(
            service: plan.service, servers: plan.currentServers, savedAt: Date())
        try? save(backup)
    }

    /// Restores the servers recorded before the last successful switch. When
    /// nothing was recorded, this falls back to DHCP (`Empty`).
    func revert() async throws -> DNSResolverPlan {
        let backup = backup()
        let service = backup?.service ?? ""
        guard !service.isEmpty else {
            throw SwitchError.commandFailed(
                String(localized: "Nothing to revert: LanFi did not change DNS on this Mac."))
        }
        let current = (try? await currentServers(service: service)) ?? []
        let target = backup?.servers ?? []
        let plan = DNSResolverPlan(
            service: service, currentServers: current, newServers: target,
            resolverName: String(localized: "the previous setting"))
        let script = DNSResolverSwitch.authorizedScript(service: service, servers: target)
        try await Self.authorized(script)
        try? FileManager.default.removeItem(at: backupURL)
        return plan
    }

    private func save(_ backup: DNSResolverBackup) throws {
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: backupURL, options: .atomic)
    }

    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
            } catch {
                throw SwitchError.commandFailed(error.localizedDescription)
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw SwitchError.commandFailed(
                    String(decoding: errorData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    /// One authorization prompt for the whole change. `osascript` is the same
    /// mechanism the packet capture uses; there is no installed privileged
    /// helper and no stored credential.
    static func authorized(_ script: String) async throws {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let error = Pipe()
            process.standardError = error
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                throw SwitchError.commandFailed(error.localizedDescription)
            }
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if message.localizedCaseInsensitiveContains("cancel")
                    || message.localizedCaseInsensitiveContains("User canceled")
                {
                    throw SwitchError.authorizationCancelled
                }
                throw SwitchError.commandFailed(
                    message.isEmpty
                        ? String(localized: "The DNS change did not complete.")
                        : message)
            }
        }.value
    }
}
