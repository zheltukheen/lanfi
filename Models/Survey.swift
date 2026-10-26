import Foundation

struct SurveySample: Codable, Identifiable, Equatable {
    let id: UUID
    let x: Double
    let y: Double
    let rssi: Int
    let ssid: String
    let bssid: String
    let recordedAt: Date
}

struct SurveyWall: Codable, Identifiable, Equatable {
    let id: UUID
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var attenuationDb: Double

    static func new(x1: Double, y1: Double, x2: Double, y2: Double) -> SurveyWall {
        SurveyWall(id: UUID(), x1: x1, y1: y1, x2: x2, y2: y2, attenuationDb: 8)
    }
}

struct SurveyProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var imageFileName: String?
    var samples: [SurveySample]
    var walls: [SurveyWall]
    var updatedAt: Date

    static func new(name: String = "Untitled survey") -> SurveyProject {
        SurveyProject(
            id: UUID(), name: name, imageFileName: nil, samples: [], walls: [], updatedAt: Date()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, imageFileName, samples, walls, updatedAt
    }

    init(
        id: UUID,
        name: String,
        imageFileName: String?,
        samples: [SurveySample],
        walls: [SurveyWall] = [],
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.imageFileName = imageFileName
        self.samples = samples
        self.walls = walls
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        samples = try container.decodeIfPresent([SurveySample].self, forKey: .samples) ?? []
        walls = try container.decodeIfPresent([SurveyWall].self, forKey: .walls) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

final class SurveyStore {
    private let directory: URL

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi/Surveys", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Move surveys and floor plans created by the pre-rename app.
        let legacy = support.appendingPathComponent("WiFA/Surveys", isDirectory: true)
        if (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil))?.isEmpty ?? true,
            FileManager.default.fileExists(atPath: legacy.path)
        {
            let entries =
                (try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                try? FileManager.default.copyItem(at: entry, to: base.appendingPathComponent(entry.lastPathComponent))
            }
        }
    }

    func latestProject() -> SurveyProject? {
        projects().first
    }

    func projects() -> [SurveyProject] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var projects: [SurveyProject] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == "survey.json",
                let data = try? Data(contentsOf: url),
                let project = try? decoder.decode(SurveyProject.self, from: data)
            else { continue }
            projects.append(project)
        }
        return projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ project: SurveyProject, imageData: Data?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(project) else { return }
        try? FileManager.default.createDirectory(at: projectDirectory(project), withIntermediateDirectories: true)
        try? data.write(to: projectDirectory(project).appendingPathComponent("survey.json"), options: .atomic)
        if let imageData, let name = project.imageFileName {
            try? imageData.write(to: projectDirectory(project).appendingPathComponent(name), options: .atomic)
        }
    }

    func imageData(for project: SurveyProject) -> Data? {
        guard let name = project.imageFileName else { return nil }
        return try? Data(contentsOf: projectDirectory(project).appendingPathComponent(name))
    }

    private func projectDirectory(_ project: SurveyProject) -> URL {
        directory.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }
}
