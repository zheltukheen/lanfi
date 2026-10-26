import Foundation

enum RemoteSensorError: LocalizedError {
    case invalidSensor
    case sshFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidSensor: return "Host, user or port is invalid."
        case .sshFailed(let message): return message
        case .invalidResponse(let message): return message
        }
    }
}

enum RemoteSensorService {
    static func validate(_ sensor: RemoteSensor) throws {
        let host = sensor.host.trimmingCharacters(in: .whitespaces)
        let user = sensor.username.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.hasPrefix("-"),
            host.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil,
            !user.isEmpty, user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
            (1...65535).contains(sensor.port)
        else {
            throw RemoteSensorError.invalidSensor
        }
    }

    static func sshArguments(for sensor: RemoteSensor) throws -> [String] {
        try validate(sensor)
        var args = [
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8",
            "-p", String(sensor.port),
        ]
        if let identity = sensor.identityFile?.trimmingCharacters(in: .whitespaces), !identity.isEmpty {
            args.append(contentsOf: ["-i", identity])
        }
        args.append("\(sensor.username)@\(sensor.host)")
        args.append("system_profiler SPAirPortDataType -json")
        return args
    }

    static func scan(_ sensor: RemoteSensor) async throws -> [RemoteNetwork] {
        let arguments = try sshArguments(for: sensor)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let errorText = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw RemoteSensorError.sshFailed(
                errorText.isEmpty ? "ssh failed with status \(process.terminationStatus)." : errorText
            )
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [RemoteNetwork] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPAirPortDataType"] as? [[String: Any]]
        else {
            throw RemoteSensorError.invalidResponse("The remote response is not SPAirPortDataType JSON.")
        }
        var networks:
            [(
                ssid: String, channel: Int, band: String, width: Int, phy: String, rssi: Int, noise: Int?,
                security: String
            )] = []
        for section in sections {
            for interface in section["spairport_airport_interfaces"] as? [[String: Any]] ?? [] {
                for item in interface["spairport_airport_other_local_wireless_networks"] as? [[String: Any]] ?? [] {
                    guard let parsed = parseNetwork(item) else { continue }
                    networks.append(parsed)
                }
                if let current = interface["spairport_current_network_information"] as? [String: Any],
                    let parsed = parseNetwork(current)
                {
                    networks.insert(parsed, at: 0)
                }
            }
        }

        return
            networks
            .map {
                RemoteNetwork(
                    id: UUID(), ssid: $0.ssid, channel: $0.channel, band: $0.band,
                    widthMHz: $0.width, phy: $0.phy, rssi: $0.rssi, noise: $0.noise,
                    security: $0.security
                )
            }
            .reduce(into: [RemoteNetwork]()) { result, network in
                if !result.contains(where: {
                    $0.ssid == network.ssid && $0.channel == network.channel && $0.rssi == network.rssi
                }) {
                    result.append(network)
                }
            }
    }

    private static func parseNetwork(_ item: [String: Any]) -> (
        ssid: String, channel: Int, band: String, width: Int, phy: String, rssi: Int, noise: Int?,
        security: String
    )? {
        let rawName = item["_name"] as? String ?? ""
        let ssid = rawName.isEmpty || rawName.contains("redacted") ? "Hidden" : rawName
        let channelText = item["spairport_network_channel"] as? String ?? ""
        let channel = Int(channelText.split(separator: " ").first ?? "") ?? 0
        let band: String
        if channelText.contains("6GHz") {
            band = "6 GHz"
        } else if channelText.contains("5GHz") {
            band = "5 GHz"
        } else if channelText.contains("2GHz") {
            band = "2.4 GHz"
        } else {
            band = "Unknown"
        }
        let width =
            Int(
                channelText.split(separator: ",").last?
                    .replacingOccurrences(of: "MHz", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " )")) ?? ""
            ) ?? 0
        let signal = item["spairport_signal_noise"] as? String ?? ""
        let numbers = signal.split(whereSeparator: { !$0.isNumber && $0 != "-" }).compactMap { Int($0) }
        guard let rssi = numbers.first, rssi < 0 else { return nil }
        let noise = numbers.count > 1 ? numbers[1] : nil
        return (
            ssid, channel, band, width,
            item["spairport_network_phymode"] as? String ?? "—",
            rssi, noise,
            securityLabel(item["spairport_security_mode"] as? String ?? "")
        )
    }

    private static func securityLabel(_ raw: String) -> String {
        let value = raw.replacingOccurrences(of: "spairport_security_mode_", with: "")
            .replacingOccurrences(of: "_", with: " ")
        if value.isEmpty { return "Open" }
        return value.uppercased()
    }
}
