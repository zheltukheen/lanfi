import Foundation

/// One support destination from the repository's `.github/FUNDING.yml`.
/// GitHub renders the same file on the repository's "Sponsor" button, so the
/// app and the web page stay in step.
public struct FundingOption: Identifiable, Equatable, Sendable {
    public let platform: String
    public let account: String?
    public let title: String
    public let detail: String
    public let url: URL
    /// SF Symbol name the UI can use without knowing the platform table.
    public let icon: String

    public init(
        platform: String, account: String?, title: String, detail: String, url: URL,
        icon: String
    ) {
        self.platform = platform
        self.account = account
        self.title = title
        self.detail = detail
        self.url = url
        self.icon = icon
    }

    public var id: String { url.absoluteString }
}

/// Parses the small YAML dialect GitHub uses for FUNDING.yml: one key per
/// platform, a scalar or inline `[…]` list, and the optional block list for
/// `custom`. Unknown keys and comments are ignored instead of failing.
public enum FundingCatalog {
    /// Title, icon and URL builder for every key GitHub documents.
    private static let platforms: [String: (title: String, icon: String, base: String)] = [
        "github": ("GitHub Sponsors", "heart.circle", "https://github.com/sponsors/"),
        "patreon": ("Patreon", "p.circle", "https://www.patreon.com/"),
        "open_collective": (
            "Open Collective", "person.3", "https://opencollective.com/"
        ),
        "ko_fi": ("Ko-fi", "cup.and.saucer", "https://ko-fi.com/"),
        "tidelift": (
            "Tidelift", "shippingbox", "https://tidelift.com/funding/github/"
        ),
        "community_bridge": (
            "Community Bridge", "building.columns",
            "https://funding.communitybridge.org/projects/"
        ),
        "liberapay": ("Liberapay", "arrow.triangle.2.circlepath", "https://liberapay.com/"),
        "issuehunt": ("IssueHunt", "ladybug", "https://issuehunt.io/r/"),
        "lfx_crowdfunding": (
            "LFX Crowdfunding", "building.2",
            "https://crowdfunding.lfx.linuxfoundation.org/projects/"
        ),
        "polar": ("Polar", "snowflake", "https://polar.sh/"),
        "buy_me_a_coffee": (
            "Buy Me a Coffee", "cup.and.saucer.fill", "https://www.buymeacoffee.com/"
        ),
        "thanks_dev": ("Thanks.dev", "hands.clap", "https://thanks.dev/"),
    ]

    /// Titles for the `custom` URLs this project actually uses, keyed by host.
    private static let customHosts: [String: String] = [
        "boosty.to": "Boosty",
        "www.boosty.to": "Boosty",
        "patreon.com": "Patreon",
        "www.patreon.com": "Patreon",
        "buymeacoffee.com": "Buy Me a Coffee",
        "www.buymeacoffee.com": "Buy Me a Coffee",
        "ko-fi.com": "Ko-fi",
        "github.com": "GitHub Sponsors",
    ]

    public static func parse(_ yaml: String) -> [FundingOption] {
        var options: [FundingOption] = []
        var seen = Set<String>()
        var blockKey: String?

        func append(_ platform: String, _ rawValue: String) {
            guard let option = option(platform: platform, value: rawValue),
                seen.insert(option.id).inserted
            else { return }
            options.append(option)
        }

        for rawLine in yaml.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("- ") {
                if let blockKey {
                    append(blockKey, unquote(String(line.dropFirst(2))))
                }
                continue
            }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            blockKey = nil

            if value.isEmpty {
                // A bare key opens a block list (`custom:` / `- url`).
                blockKey = key
                continue
            }
            if value.hasPrefix("["), value.hasSuffix("]") {
                value = String(value.dropFirst().dropLast())
                for part in splitList(value) {
                    append(key, part)
                }
                continue
            }
            for part in splitList(value) {
                append(key, part)
            }
        }
        return options
    }

    public static func option(platform: String, value rawValue: String) -> FundingOption? {
        let value = unquote(rawValue).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.lowercased().contains("replace with") else { return nil }

        if platform == "custom" {
            guard let url = URL(string: value), let scheme = url.scheme,
                scheme == "https" || scheme == "http"
            else { return nil }
            let host = url.host ?? ""
            let title =
                customHosts[host]
                ?? Self.platforms.values.first { $0.base.contains(host) }?.title
                ?? host.replacingOccurrences(of: "www.", with: "")
                .split(separator: ".").first.map { $0.capitalized } ?? "Website"
            return FundingOption(
                platform: platform, account: nil, title: title,
                detail: host.replacingOccurrences(of: "www.", with: ""),
                url: url, icon: "heart.fill")
        }

        guard let entry = platforms[platform] else { return nil }
        let account = value.hasPrefix("@") ? String(value.dropFirst()) : value
        guard !account.isEmpty, !account.contains(" ") else { return nil }

        if account.contains("://"), let url = URL(string: account) {
            return FundingOption(
                platform: platform, account: nil, title: entry.title, detail: url.host ?? account,
                url: url, icon: entry.icon)
        }

        guard let url = URL(string: entry.base + account) else { return nil }
        return FundingOption(
            platform: platform, account: account, title: entry.title, detail: account,
            url: url, icon: entry.icon)
    }

    // MARK: - YAML-lite helpers

    private static func stripComment(_ line: String) -> String {
        var result = ""
        var inSingle = false
        var inDouble = false
        var previous: Character = " "
        for character in line {
            if character == "'", !inDouble {
                inSingle.toggle()
            } else if character == "\"", !inSingle {
                inDouble.toggle()
            }
            if character == "#", !inSingle, !inDouble, previous.isWhitespace {
                break
            }
            result.append(character)
            previous = character
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2,
            (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
                || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
        {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// Splits `a, b` or `'a, b'` without breaking inside quotes.
    private static func splitList(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for character in value {
            if character == "'", !inDouble {
                inSingle.toggle()
            } else if character == "\"", !inSingle {
                inDouble.toggle()
            }
            if character == ",", !inSingle, !inDouble {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts.map { unquote($0) }.filter { !$0.isEmpty }
    }
}
