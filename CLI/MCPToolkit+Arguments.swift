import Foundation

extension MCPToolkit {
    // MARK: - Argument helpers

    static let assetDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(_ arguments: [String: Any], _ key: String) -> String? {
        guard let value = arguments[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func int(_ arguments: [String: Any], _ key: String) -> Int? {
        if let value = arguments[key] as? Int { return value }
        if let value = arguments[key] as? Double { return Int(value) }
        if let value = arguments[key] as? NSNumber { return value.intValue }
        if let value = arguments[key] as? String { return Int(value) }
        return nil
    }

    static func double(_ arguments: [String: Any], _ key: String) -> Double? {
        if let value = arguments[key] as? Double { return value }
        if let value = arguments[key] as? Int { return Double(value) }
        if let value = arguments[key] as? NSNumber { return value.doubleValue }
        if let value = arguments[key] as? String { return Double(value) }
        return nil
    }

    static func flag(_ arguments: [String: Any], _ key: String) -> Bool {
        if let value = arguments[key] as? Bool { return value }
        if let value = arguments[key] as? String { return value == "true" || value == "1" }
        return false
    }

    static func hostArgument(_ arguments: [String: Any]) throws -> String {
        guard let host = string(arguments, "host") else {
            throw MCPToolArgumentError.message("Pass `host`.")
        }
        return host
    }

    static func ports(_ arguments: [String: Any], fallback: String) -> [UInt16] {
        let spec = string(arguments, "ports") ?? fallback
        return (try? PortSpec.parse(spec)) ?? []
    }
}
