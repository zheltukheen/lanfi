import Foundation
import UserNotifications

protocol UptimeChecking: Sendable {
    func check(_ target: UptimeTarget) async -> UptimeCheck
}

struct SystemUptimeChecker: UptimeChecking {
    func check(_ target: UptimeTarget) async -> UptimeCheck {
        switch target.kind {
        case .http:
            return await checkHTTP(target)
        case .tcp:
            return await checkTCP(target)
        case .tls:
            return await checkTLS(target)
        case .dns:
            return await checkDNS(target)
        case .mail:
            return await checkMail(target)
        }
    }

    private func checkHTTP(_ target: UptimeTarget) async -> UptimeCheck {
        guard let url = target.httpURL else {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: "Invalid HTTP URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let started = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let milliseconds = Date().timeIntervalSince(started) * 1000
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isUp = (200..<400).contains(code)
            return UptimeCheck(
                targetID: target.id,
                isUp: isUp,
                latencyMilliseconds: milliseconds,
                detail: "HTTP \(code)"
            )
        } catch {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: error.localizedDescription)
        }
    }

    private func checkTLS(_ target: UptimeTarget) async -> UptimeCheck {
        guard let parsed = target.tlsTarget, let port = parsed.port else {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: "Invalid TLS address")
        }
        let started = Date()
        do {
            let report = try await URLSessionTLSCertificateInspector().inspect(
                host: parsed.host, port: port, timeout: 10)
            let milliseconds = Date().timeIntervalSince(started) * 1000
            let days = report.daysRemaining
            let up = report.trusted && !report.expired
            let detail =
                report.expired
                ? String(localized: "TLS certificate expired")
                : report.trusted
                    ? String(
                        format: String(localized: "TLS trusted · %lld days left"),
                        days ?? 0)
                    : String(localized: "TLS certificate is not trusted")
            return UptimeCheck(
                targetID: target.id,
                isUp: up,
                latencyMilliseconds: milliseconds,
                detail: detail
            )
        } catch {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: error.localizedDescription)
        }
    }

    private func checkDNS(_ target: UptimeTarget) async -> UptimeCheck {
        guard let host = target.dnsHost else {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: "Invalid DNS hostname")
        }
        let started = Date()
        do {
            let result = try await UDPDNSClient().lookup(
                host: host, type: .a, resolver: .system, timeout: 8)
            let milliseconds = Date().timeIntervalSince(started) * 1000
            let values = result.records.map(\.value)
            return UptimeCheck(
                targetID: target.id,
                isUp: !values.isEmpty,
                latencyMilliseconds: milliseconds,
                detail: values.isEmpty
                    ? String(localized: "No A records")
                    : "A \(values.prefix(2).joined(separator: ", "))"
            )
        } catch {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: error.localizedDescription)
        }
    }

    private func checkMail(_ target: UptimeTarget) async -> UptimeCheck {
        guard let domain = target.mailDomain else {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: "Invalid mail domain")
        }
        let started = Date()
        let report = await DNSMailLookupService().lookup(
            domain: domain, resolver: .system)
        let milliseconds = Date().timeIntervalSince(started) * 1000
        let coreChecks = report.hasMX && report.hasSPF && report.hasDMARC
        return UptimeCheck(
            targetID: target.id,
            isUp: coreChecks,
            latencyMilliseconds: milliseconds,
            detail: String(
                format: String(localized: "Mail checks %lld/4 · %lld issues"),
                report.passedChecks, report.issues.count)
        )
    }

    private func checkTCP(_ target: UptimeTarget) async -> UptimeCheck {
        guard let parsed = target.tcpTarget, let port = parsed.port else {
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: "Invalid TCP address")
        }
        switch await TCPProbe.connect(host: parsed.host, port: port, timeout: 8) {
        case .open(let milliseconds):
            return UptimeCheck(
                targetID: target.id,
                isUp: true,
                latencyMilliseconds: milliseconds,
                detail: "TCP \(port) open"
            )
        case .closed(_, let detail):
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: detail ?? "Connection refused")
        case .filtered(let detail):
            return UptimeCheck(
                targetID: target.id, isUp: false, detail: detail ?? "No response")
        }
    }
}

protocol UserNotifying: Sendable {
    func notify(title: String, body: String) async
}

struct SystemUserNotifier: UserNotifying {
    func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard
            settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

@MainActor
final class UptimeMonitor: ObservableObject {
    @Published private(set) var targets: [UptimeTarget] = []
    @Published private(set) var checks: [UptimeCheck] = []
    @Published private(set) var isChecking = false
    @Published var errorMessage: String?

    private let store: UptimeStore
    private let checker: any UptimeChecking
    private let notifier: any UserNotifying
    private var loopTask: Task<Void, Never>?
    private let retention: TimeInterval = 7 * 24 * 60 * 60

    init(
        store: UptimeStore = UptimeStore(),
        checker: any UptimeChecking = SystemUptimeChecker(),
        notifier: any UserNotifying = SystemUserNotifier(),
        startAutomatically: Bool = true
    ) {
        self.store = store
        self.checker = checker
        self.notifier = notifier
        let snapshot = store.load()
        targets = snapshot.targets
        checks = snapshot.checks
        if targets.isEmpty, checks.isEmpty {
            targets = UptimeTarget.starterTargets
            save()
        }
        if startAutomatically { start() }
    }

    var downTargets: [UptimeTarget] {
        targets.filter { target in
            target.enabled && state(for: target).isUp == false
        }
    }

    var downCount: Int { downTargets.count }

    func state(for target: UptimeTarget) -> UptimeTargetState {
        let targetChecks =
            checks
            .filter { $0.targetID == target.id }
            .sorted { $0.at < $1.at }
        let last = targetChecks.last
        let upCount = targetChecks.filter(\.isUp).count
        var outages = 0
        var previous: Bool?
        for check in targetChecks {
            if UptimeTransition.event(previousUp: previous, currentUp: check.isUp) == .down {
                outages += 1
            }
            previous = check.isUp
        }
        let latencies = targetChecks.compactMap(\.latencyMilliseconds)
        return UptimeTargetState(
            target: target,
            lastCheck: last,
            uptimePercent: targetChecks.isEmpty
                ? nil : Double(upCount) / Double(targetChecks.count) * 100,
            averageLatencyMilliseconds: latencies.isEmpty
                ? nil : latencies.reduce(0, +) / Double(latencies.count),
            outageCount: outages,
            checks: targetChecks
        )
    }

    func add(_ target: UptimeTarget, checkImmediately: Bool = true) {
        targets.append(target)
        save()
        if checkImmediately {
            Task { await self.checkNow(target.id) }
        }
    }

    func add(
        name: String,
        address: String,
        kind: UptimeTargetKind,
        intervalMinutes: Int
    ) -> Bool {
        guard
            let target = UptimeTarget.make(
                name: name, address: address, kind: kind, intervalMinutes: intervalMinutes)
        else { return false }
        add(target)
        return true
    }

    func remove(_ target: UptimeTarget) {
        targets.removeAll { $0.id == target.id }
        checks.removeAll { $0.targetID == target.id }
        save()
    }

    func setEnabled(_ enabled: Bool, for target: UptimeTarget) {
        guard let index = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[index].enabled = enabled
        save()
        if enabled {
            Task { await self.checkNow(target.id) }
        }
    }

    func checkNow(_ targetID: UUID) async {
        guard let target = targets.first(where: { $0.id == targetID }) else { return }
        await perform(target)
    }

    func checkAllNow() async {
        for target in targets where target.enabled {
            await perform(target)
        }
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkDue()
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func checkDue() async {
        let now = Date()
        let due = targets.filter { target in
            guard target.enabled else { return false }
            guard
                let last =
                    checks
                    .filter({ $0.targetID == target.id })
                    .max(by: { $0.at < $1.at })
            else { return true }
            return now.timeIntervalSince(last.at) >= Double(target.intervalMinutes) * 60
        }
        for target in due {
            await perform(target)
        }
    }

    private func perform(_ target: UptimeTarget) async {
        isChecking = true
        defer { isChecking = false }
        let previous =
            checks
            .filter { $0.targetID == target.id }
            .max { $0.at < $1.at }
        let result = await checker.check(target)
        checks.append(result)
        trimChecks(now: result.at)
        save()

        if let event = UptimeTransition.event(
            previousUp: previous?.isUp, currentUp: result.isUp)
        {
            let title =
                event == .down
                ? "\(target.name) is down"
                : "\(target.name) is back up"
            await notifier.notify(
                title: title, body: result.detail ?? target.address)
        }
    }

    private func save() {
        store.save(UptimeStoreSnapshot(targets: targets, checks: checks))
    }

    private func trimChecks(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        checks.removeAll { $0.at < cutoff }
        if checks.count > 5_000 {
            checks.removeFirst(checks.count - 5_000)
        }
    }
}
