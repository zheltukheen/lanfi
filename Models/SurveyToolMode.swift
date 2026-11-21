import Foundation

/// What a click on the plan does.
///
/// One value instead of four independent booleans: with separate flags a user
/// could switch on walls and predictive access points at the same time, and the
/// click order silently decided which of them happened. The tool the inspector
/// names is now always the tool that runs.
enum SurveyToolMode: String, CaseIterable, Identifiable, Sendable {
    case sample
    case walk
    case wall
    case room
    case predictive
    case calibrate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sample: return String(localized: "Record sample")
        case .walk: return String(localized: "Walk sampling")
        case .wall: return String(localized: "Draw wall")
        case .room: return String(localized: "Draw room")
        case .predictive: return String(localized: "Predictive AP")
        case .calibrate: return String(localized: "Calibrate scale")
        }
    }

    /// Fits a narrow chip in the inspector; `title` is the full sentence.
    var shortTitle: String {
        switch self {
        case .sample: return String(localized: "Sample")
        case .walk: return String(localized: "Walk")
        case .wall: return String(localized: "Wall")
        case .room: return String(localized: "Room")
        case .predictive: return String(localized: "AP")
        case .calibrate: return String(localized: "Scale")
        }
    }

    var icon: String {
        switch self {
        case .sample: return "hand.tap"
        case .walk: return "figure.walk"
        case .wall: return "pencil.tip"
        case .room: return "rectangle.dashed"
        case .predictive: return "antenna.radiowaves.left.and.right"
        case .calibrate: return "ruler"
        }
    }

    /// Tones are named here so the model stays free of SwiftUI; the view maps
    /// them onto `AppPalette`.
    enum Tone: Sendable {
        case accent
        case green
        case orange
        case purple
        case cyan
    }

    var tone: Tone {
        switch self {
        case .sample: return .accent
        case .walk: return .green
        case .wall, .room: return .orange
        case .predictive: return .purple
        case .calibrate: return .cyan
        }
    }

    var hint: String {
        switch self {
        case .sample:
            return String(
                localized: "Click anywhere on the plan to capture the selected network's signal.")
        case .walk:
            return String(
                localized: "Move the pointer over the plan to sample automatically as you walk.")
        case .wall:
            return String(localized: "Click two points to draw a wall. Walls attenuate the heatmap.")
        case .room:
            return String(
                localized: "Click the room corners, then choose Finish Room from Structure.")
        case .predictive:
            return String(
                localized:
                    "Click the plan to place a virtual access point and render predicted coverage.")
        case .calibrate:
            return String(localized: "Click two points that have a known real-world distance.")
        }
    }

    /// Short line for the status strip when the mode is chosen.
    var activationMessage: String {
        switch self {
        case .sample: return String(localized: "Record mode: click the plan to add a sample.")
        case .walk: return String(localized: "Walk mode: move the pointer over the plan to sample automatically.")
        case .wall: return String(localized: "Wall mode: click two points to draw a wall.")
        case .room: return String(localized: "Room mode: click vertices, then Finish Room.")
        case .predictive: return String(localized: "Predictive mode: click the plan to place an AP.")
        case .calibrate: return String(localized: "Calibration: click two points and enter the real distance.")
        }
    }

    /// Modes that draw on the plan need a crosshair rather than an arrow.
    var isDrawing: Bool {
        self == .wall || self == .room || self == .predictive || self == .calibrate || self == .walk
    }
}
