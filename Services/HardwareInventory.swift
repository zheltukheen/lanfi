import Foundation

struct DetectedHardware: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
}

enum HardwareInventory {
    private static let categories: [(String, [String])] = [
        ("Spectrum analyzer", ["wi-spy", "metageek", "wispy", "rf explorer", "spectrum"]),
        ("WLAN Pi", ["wlan pi", "wlanpi"]),
        ("802.15.4 / Zigbee", ["zigbee", "802.15.4", "thread", "sonoff", "conbee"]),
        ("SDR", ["rtl-sdr", "hackrf", "airspy", "sdr"]),
    ]

    static func detect() async -> [DetectedHardware] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPUSBDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return parse(data)
        } catch {
            return []
        }
    }

    static func parse(_ data: Data) -> [DetectedHardware] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var names: [String] = []
        collectNames(object, into: &names)
        let matched: [DetectedHardware] = names.compactMap { name -> DetectedHardware? in
            let lower = name.lowercased()
            guard
                let category = categories.first(where: { entry in
                    entry.1.contains { lower.contains($0) }
                })?.0
            else { return nil }
            return DetectedHardware(id: name, name: name, category: category)
        }
        var unique: [DetectedHardware] = []
        for item in matched where !unique.contains(where: { $0.id == item.id }) {
            unique.append(item)
        }
        return unique
    }

    private static func collectNames(_ object: Any, into names: inout [String]) {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if key == "_name", let name = value as? String { names.append(name) }
                collectNames(value, into: &names)
            }
        } else if let array = object as? [Any] {
            for value in array { collectNames(value, into: &names) }
        }
    }
}
