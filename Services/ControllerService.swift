import Foundation

enum ControllerError: LocalizedError {
    case invalidURL
    case missingToken
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Controller URL is invalid."
        case .missingToken: return "API token is missing."
        case .http(let code, let message): return "HTTP \(code): \(message)"
        case .invalidResponse: return "Unexpected controller response."
        }
    }
}

enum ControllerService {
    static func request(for account: ControllerAccount) throws -> URLRequest {
        guard let base = URL(string: account.baseURL), let scheme = base.scheme,
            scheme == "https" || scheme == "http"
        else { throw ControllerError.invalidURL }
        let url: URL
        switch account.kind {
        case .unifi:
            let site = account.siteOrOrg.isEmpty ? "default" : account.siteOrOrg
            url = base.appendingPathComponent("proxy/network/api/s/\(site)/stat/device")
        case .meraki:
            url = URL(string: "https://api.meraki.com/api/v1/organizations/\(account.siteOrOrg)/devices")!
        }
        guard let token = ControllerKeychain.token(for: account.id), !token.isEmpty else {
            throw ControllerError.missingToken
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        switch account.kind {
        case .unifi: request.setValue(token, forHTTPHeaderField: "X-API-KEY")
        case .meraki: request.setValue(token, forHTTPHeaderField: "X-Cisco-Meraki-API-Key")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func fetchAccessPoints(_ account: ControllerAccount) async throws -> [ControllerAccessPoint] {
        let (data, response) = try await URLSession.shared.data(for: request(for: account))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(decoding: data, as: UTF8.self)
            throw ControllerError.http(http.statusCode, String(message.prefix(240)))
        }
        return try parse(data, kind: account.kind)
    }

    static func parse(_ data: Data, kind: ControllerKind) throws -> [ControllerAccessPoint] {
        let root = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        switch kind {
        case .unifi:
            guard let root = root as? [String: Any], let data = root["data"] as? [[String: Any]] else {
                throw ControllerError.invalidResponse
            }
            rows = data
        case .meraki:
            guard let array = root as? [[String: Any]] else { throw ControllerError.invalidResponse }
            rows = array
        }
        return rows.compactMap { row in
            let name = (row["name"] as? String) ?? (row["model"] as? String) ?? "AP"
            let mac = (row["mac"] as? String) ?? ""
            let model = (row["model"] as? String) ?? "—"
            let ip = (row["ip"] as? String) ?? (row["lanIp"] as? String) ?? "—"
            let id = (row["_id"] as? String) ?? (row["serial"] as? String) ?? mac
            guard !id.isEmpty else { return nil }
            return ControllerAccessPoint(id: id, name: name, mac: mac, model: model, ip: ip)
        }
    }
}
