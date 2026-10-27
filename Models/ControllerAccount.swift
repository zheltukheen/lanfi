import Foundation

enum ControllerKind: String, Codable, CaseIterable, Identifiable {
    case unifi
    case meraki

    var id: String { rawValue }
    var title: String { self == .unifi ? "UniFi" : "Meraki" }
    var endpointHint: String {
        self == .unifi ? "https://controller:8443" : "https://api.meraki.com"
    }
}

struct ControllerAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ControllerKind
    var name: String
    var baseURL: String
    var siteOrOrg: String

    static func new(kind: ControllerKind, name: String, baseURL: String, siteOrOrg: String) -> ControllerAccount {
        ControllerAccount(id: UUID(), kind: kind, name: name, baseURL: baseURL, siteOrOrg: siteOrOrg)
    }
}

struct ControllerAccessPoint: Identifiable, Equatable {
    let id: String
    let name: String
    let mac: String
    let model: String
    let ip: String
}

final class ControllerAccountStore {
    private let defaults: UserDefaults
    private let key = "Wifa.controllerAccounts"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [ControllerAccount] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ControllerAccount].self, from: data)) ?? []
    }

    func save(_ accounts: [ControllerAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: key)
    }
}

enum ControllerKeychain {
    private static let service = "ru.zheltukheen.LanFi.Controllers"

    static func save(_ token: String, for id: UUID) {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !token.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func token(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
