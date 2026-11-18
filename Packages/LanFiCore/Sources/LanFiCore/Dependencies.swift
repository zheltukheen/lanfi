import Foundation

// MARK: - Clock

/// Time is a dependency, not a global: stores and monitors take a clock so
/// their tests do not sleep and their behaviour is reproducible.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock frozen at one instant, advanced explicitly by the test.
public final class FixedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = now
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }

    public func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}

// MARK: - Settings storage

/// The narrow slice of `UserDefaults` the settings layer needs, so tests can
/// substitute an in-memory store and the store never reaches for `.standard`.
public protocol SettingsStorage: Sendable {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func double(forKey key: String) -> Double
    func integer(forKey key: String) -> Int
    func bool(forKey key: String) -> Bool
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

public struct UserDefaultsSettingsStorage: SettingsStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func double(forKey key: String) -> Double { defaults.double(forKey: key) }
    public func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    public func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
    public func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}

// MARK: - Notifications

/// Posting a "settings changed" announcement is a side effect a test can
/// observe without a running `NotificationCenter`.
public protocol NotificationPosting: Sendable {
    func post(_ name: Notification.Name, userInfo: [String: String]?)
}

public struct NotificationCenterPoster: NotificationPosting {
    public init() {}

    public func post(_ name: Notification.Name, userInfo: [String: String]?) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }
}

public struct SilentNotificationPoster: NotificationPosting {
    public init() {}
    public func post(_ name: Notification.Name, userInfo: [String: String]?) {}
}

extension Notification.Name {
    /// Posted after `AppSettingsStore.save`/`import`/`reset`.
    public static let lanFiSettingsDidChange = Notification.Name("LanFi.settingsDidChange")
}

// MARK: - File store

/// Reading and writing settings files is injected so export/import can be
/// tested without touching the user's disk.
public protocol FileStoring: Sendable {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

public struct FileStore: FileStoring {
    public init() {}

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
