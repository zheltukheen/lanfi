import Foundation

/// A network saved in System Settings. Read-only: LanFi never reads or writes
/// Wi-Fi passwords, it only lists the preferred-network names.
struct KnownNetwork: Identifiable, Equatable {
    let ssid: String

    var id: String { ssid }
}

enum KnownNetworksParser {
    /// Parses `networksetup -listpreferredwirelessnetworks <if>` output. The
    /// first line is a header ("Preferred networks on en0:").
    static func parse(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Preferred networks on") }
    }
}

/// `WIFI:` join payload for a guest QR code. The user supplies the password;
/// it is never stored or read from the Keychain.
enum WiFiQRPayload {
    enum Security: String, CaseIterable, Identifiable {
        case wpa
        case wep
        case open

        var id: String { rawValue }

        var title: String {
            switch self {
            case .wpa: return "WPA/WPA2/WPA3"
            case .wep: return "WEP"
            case .open: return "Open"
            }
        }

        var token: String {
            switch self {
            case .wpa: return "WPA"
            case .wep: return "WEP"
            case .open: return "nopass"
            }
        }
    }

    /// Format documented by the ZXing "WIFI:" scheme: `WIFI:T:WPA;S:ssid;P:pass;;`
    static func string(ssid: String, password: String, security: Security) -> String {
        var parts = ["T:\(security.token)", "S:\(escape(ssid))"]
        if security != .open, !password.isEmpty {
            parts.append("P:\(escape(password))")
        }
        return "WIFI:" + parts.joined(separator: ";") + ";;"
    }

    /// `\`, `;`, `,`, `"` and `:` are special in the payload.
    private static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            if #"\\;,\":"#.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
