import Foundation

struct ScanSession: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    let networks: [NetworkModel]
    let annotations: [String: NetworkAnnotation]

    var networkCount: Int { networks.count }
    var displayName: String { name.isEmpty ? "Untitled session" : name }
}

final class SessionStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi/Sessions", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Move sessions created by the pre-rename app.
        let legacy = support.appendingPathComponent("WiFA/Sessions", isDirectory: true)
        if (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil))?.isEmpty ?? true,
            FileManager.default.fileExists(atPath: legacy.path)
        {
            let files =
                (try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? FileManager.default.copyItem(at: file, to: base.appendingPathComponent(file.lastPathComponent))
            }
        }

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func save(name: String, networks: [NetworkModel], annotations: [String: NetworkAnnotation]) throws -> ScanSession {
        let session = ScanSession(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            networks: networks,
            annotations: annotations
        )
        let data = try encoder.encode(session)
        try data.write(to: fileURL(for: session), options: .atomic)
        return session
    }

    func sessions() -> [ScanSession] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        return
            urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ScanSession.self, from: data)
            }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    @discardableResult
    func delete(_ session: ScanSession) -> Bool {
        (try? FileManager.default.removeItem(at: fileURL(for: session))) != nil
    }

    private func fileURL(for session: ScanSession) -> URL {
        directory.appendingPathComponent("\(session.id.uuidString).json")
    }
}
