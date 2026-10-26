import Foundation

struct NetworkAnnotation: Codable, Equatable {
    var alias: String = ""
    var notes: String = ""
    var tags: [String] = []
    var colorHex: String?
    var updatedAt: Date = .distantPast

    var isEmpty: Bool {
        alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tags.isEmpty
            && (colorHex ?? "").isEmpty
    }

    var displayAlias: String? {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

final class AnnotationStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "ru.zheltukheen.LanFi.annotations")
    private var saveWorkItem: DispatchWorkItem?

    private(set) var annotations: [String: NetworkAnnotation]

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("annotations.json")

        // Preserve annotations created before the LanFi rename.
        let legacy = support.appendingPathComponent("WiFA/annotations.json")
        if !FileManager.default.fileExists(atPath: fileURL.path),
            FileManager.default.fileExists(atPath: legacy.path)
        {
            try? FileManager.default.copyItem(at: legacy, to: fileURL)
        }
        annotations = Self.load(from: fileURL)
    }

    func annotation(for id: String) -> NetworkAnnotation {
        annotations[id] ?? NetworkAnnotation()
    }

    func update(_ annotation: NetworkAnnotation, for id: String) {
        if annotation.isEmpty {
            annotations.removeValue(forKey: id)
        } else {
            var value = annotation
            value.updatedAt = Date()
            annotations[id] = value
        }
        scheduleSave()
    }

    func replaceAll(_ values: [String: NetworkAnnotation]) {
        annotations = values
        saveWorkItem?.cancel()
        saveWorkItem = nil
        queue.sync { persist(annotations, to: fileURL) }
    }

    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        queue.sync { persist(annotations, to: fileURL) }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        let snapshot = annotations
        let url = fileURL
        queue.async { [weak self] in
            self?.persist(snapshot, to: url)
        }
    }

    private func persist(_ snapshot: [String: NetworkAnnotation], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> [String: NetworkAnnotation] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: NetworkAnnotation].self, from: data)) ?? [:]
    }
}
