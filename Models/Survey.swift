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

struct SurveyPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct SurveyObstacle: Codable, Identifiable, Equatable {
    let id: UUID
    var points: [SurveyPoint]
    var attenuationDb: Double

    static func new(points: [SurveyPoint], attenuationDb: Double = 8) -> SurveyObstacle {
        SurveyObstacle(id: UUID(), points: points, attenuationDb: attenuationDb)
    }
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
    var obstacles: [SurveyObstacle]
    var accessPoints: [SurveyAccessPoint]
    var floorLevel: Int
    var floorHeightMeters: Double
    var planWidthMeters: Double?
    var reportTitle: String?
    var clientName: String?
    var reportNotes: String?
    var updatedAt: Date

    static func new(name: String = "Untitled survey") -> SurveyProject {
        SurveyProject(
            id: UUID(), name: name, imageFileName: nil, samples: [], walls: [],
            obstacles: [], accessPoints: [], floorLevel: 0, floorHeightMeters: 3.0, updatedAt: Date()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, imageFileName, samples, walls, obstacles, accessPoints, floorLevel, floorHeightMeters,
            planWidthMeters
        case reportTitle, clientName, reportNotes, updatedAt
    }

    init(
        id: UUID,
        name: String,
        imageFileName: String?,
        samples: [SurveySample],
        walls: [SurveyWall] = [],
        obstacles: [SurveyObstacle] = [],
        accessPoints: [SurveyAccessPoint] = [],
        floorLevel: Int = 0,
        floorHeightMeters: Double = 3.0,
        planWidthMeters: Double? = nil,
        reportTitle: String? = nil,
        clientName: String? = nil,
        reportNotes: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.imageFileName = imageFileName
        self.samples = samples
        self.walls = walls
        self.obstacles = obstacles
        self.accessPoints = accessPoints
        self.floorLevel = floorLevel
        self.floorHeightMeters = floorHeightMeters
        self.planWidthMeters = planWidthMeters
        self.reportTitle = reportTitle
        self.clientName = clientName
        self.reportNotes = reportNotes
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        samples = try container.decodeIfPresent([SurveySample].self, forKey: .samples) ?? []
        walls = try container.decodeIfPresent([SurveyWall].self, forKey: .walls) ?? []
        obstacles = try container.decodeIfPresent([SurveyObstacle].self, forKey: .obstacles) ?? []
        accessPoints = try container.decodeIfPresent([SurveyAccessPoint].self, forKey: .accessPoints) ?? []
        floorLevel = try container.decodeIfPresent(Int.self, forKey: .floorLevel) ?? 0
        floorHeightMeters = try container.decodeIfPresent(Double.self, forKey: .floorHeightMeters) ?? 3.0
        planWidthMeters = try container.decodeIfPresent(Double.self, forKey: .planWidthMeters)
        reportTitle = try container.decodeIfPresent(String.self, forKey: .reportTitle)
        clientName = try container.decodeIfPresent(String.self, forKey: .clientName)
        reportNotes = try container.decodeIfPresent(String.self, forKey: .reportNotes)
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
