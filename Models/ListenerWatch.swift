import Foundation

/// P3.1 — one listening socket the watchdog tracks.
///
/// A TCP `LISTEN` socket and any UDP socket both answer clients, so both count
/// as listeners here. The exposure comes from the local endpoint, which is the
/// only thing `lsof` can tell us without a router table.
struct ListenerSummary: Identifiable, Equatable, Sendable {
    let id: String
    let process: String
    let pid: Int
    let user: String
    let transport: String
    let local: String
    let exposure: SocketExposure

    init(
        id: String, process: String, pid: Int, user: String, transport: String, local: String,
        exposure: SocketExposure
    ) {
        self.id = id
        self.process = process
        self.pid = pid
        self.user = user
        self.transport = transport
        self.local = local
        self.exposure = exposure
    }

    init?(connection: OpenConnection) {
        guard connection.isListener else { return nil }
        self.init(
            id: "\(connection.pid)|\(connection.transport)|\(connection.local)",
            process: connection.process,
            pid: connection.pid,
            user: connection.user,
            transport: connection.transport,
            local: connection.local,
            exposure: connection.exposure)
    }

    /// `python3 · 0.0.0.0:8000`, used by the change list and notifications.
    var label: String { "\(process) · \(local)" }
}

enum ListenerChangeKind: String, Equatable, Sendable {
    case opened
    case closed
}

struct ListenerChange: Identifiable, Equatable, Sendable {
    let id: String
    let kind: ListenerChangeKind
    let listener: ListenerSummary
    let at: Date

    var notificationTitle: String { String(localized: "LanFi · Listeners") }

    var notificationBody: String {
        switch kind {
        case .opened:
            return String(
                localized: "New listener: \(listener.process) on \(listener.local) — \(listener.exposure.title)"
            )
        case .closed:
            return String(
                localized: "Listener closed: \(listener.process) on \(listener.local)")
        }
    }
}

/// The set difference between two samples, one notification each.
enum ListenerWatchDiff {
    static func changes(
        previous: [ListenerSummary], current: [ListenerSummary], at: Date
    ) -> [ListenerChange] {
        let previousIDs = Set(previous.map(\.id))
        let currentIDs = Set(current.map(\.id))

        let opened =
            current
            .filter { !previousIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { listener in
                ListenerChange(
                    id: "opened|\(listener.id)|\(at.timeIntervalSince1970)",
                    kind: .opened, listener: listener, at: at)
            }
        let closed =
            previous
            .filter { !currentIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { listener in
                ListenerChange(
                    id: "closed|\(listener.id)|\(at.timeIntervalSince1970)",
                    kind: .closed, listener: listener, at: at)
            }
        return opened + closed
    }
}
