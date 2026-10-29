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
        case .snmp:
            throw ControllerError.invalidURL
        }
        guard let token = ControllerKeychain.token(for: account.id), !token.isEmpty else {
            throw ControllerError.missingToken
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        switch account.kind {
        case .unifi: request.setValue(token, forHTTPHeaderField: "X-API-KEY")
        case .meraki: request.setValue(token, forHTTPHeaderField: "X-Cisco-Meraki-API-Key")
        case .snmp: break
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func fetchAccessPoints(_ account: ControllerAccount) async throws -> [ControllerAccessPoint] {
        if account.kind == .snmp {
            return try await SNMPController.walk(account: account)
        }
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
        case .snmp:
            throw ControllerError.invalidResponse
        }
        return rows.compactMap { row in
            let name = (row["name"] as? String) ?? (row["model"] as? String) ?? "AP"
            let mac = (row["mac"] as? String) ?? ""
            let model = (row["model"] as? String) ?? "—"
            let ip = (row["ip"] as? String) ?? (row["lanIp"] as? String) ?? "—"
            let id = (row["_id"] as? String) ?? (row["serial"] as? String) ?? mac
            guard !id.isEmpty else { return nil }
            var channel: Int?
            var txPower: Int?
            var utilization: Int?
            var supportedChannels: [Int] = []
            if let radios = row["radio_table_stats"] as? [[String: Any]], let radio = radios.first {
                channel = radio["channel"] as? Int
                txPower = radio["tx_power"] as? Int
                utilization = (radio["cu_total"] as? Int) ?? (radio["cu_self_rx"] as? Int)
            }
            if let radios = row["radio_table"] as? [[String: Any]], let radio = radios.first {
                supportedChannels =
                    (radio["channels"] as? [Int])
                    ?? (radio["supported_channels"] as? [Int])
                    ?? (radio["allowed_channels"] as? [Int])
                    ?? []
                if channel == nil { channel = radio["channel"] as? Int }
            }
            let clients = (row["num_sta"] as? Int) ?? (row["clientCount"] as? Int)
            return ControllerAccessPoint(
                id: id, name: name, mac: mac, model: model, ip: ip,
                channel: channel, clients: clients, txPower: txPower, utilization: utilization,
                supportedChannels: supportedChannels
            )
        }
    }
}

enum SNMPController {
    static func walk(account: ControllerAccount) async throws -> [ControllerAccessPoint] {
        guard let token = ControllerKeychain.token(for: account.id), !token.isEmpty else {
            throw ControllerError.missingToken
        }
        let host = account.baseURL.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.hasPrefix("-") else { throw ControllerError.invalidURL }
        let oid = account.siteOrOrg.isEmpty ? "1.3.6.1.2.1.1" : account.siteOrOrg
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
        process.arguments = ["-v2c", "-c", token, "-On", "-Oq", host, oid]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ControllerError.http(Int(process.terminationStatus), message)
        }
        return parse(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    static func parse(_ text: String) -> [ControllerAccessPoint] {
        text.split(whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            var name = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("=") { name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces) }
            return ControllerAccessPoint(
                id: String(parts[0]), name: name, mac: "", model: "SNMP", ip: "—"
            )
        }
    }
}
