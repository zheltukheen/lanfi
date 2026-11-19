import Foundation

/// P3.10 — one plain-language description of a network service.
///
/// `source` matters for honesty: a bundled answer works offline and is the same
/// every time, while a generated one comes from the on-device model and is
/// labelled as such.
struct ServiceDescription: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case bundled
        case onDeviceModel
        case unknown
    }

    let title: String
    let category: String
    let source: Source

    static let unknownService = ServiceDescription(
        title: String(localized: "Unknown service"),
        category: String(localized: "Unclassified"),
        source: .unknown)
}

/// The bundled map. It is deliberately small and offline: the domains and
/// processes a Mac meets every day, each with a one-line answer.
enum ServiceDescriptionCatalog {
    private struct Entry {
        let pattern: String
        let title: String
        let category: String
    }

    // MARK: - Domains

    private static let domainEntries: [Entry] = [
        Entry(pattern: "gateway.icloud.com", title: applePush, category: apple),
        Entry(pattern: ".push.apple.com", title: applePush, category: apple),
        Entry(pattern: ".icloud.com", title: iCloud, category: apple),
        Entry(pattern: "time.apple.com", title: appleTime, category: apple),
        Entry(pattern: ".time.apple.com", title: appleTime, category: apple),
        Entry(pattern: "ocsp.apple.com", title: appleCertificate, category: apple),
        Entry(pattern: "ocsp2.apple.com", title: appleCertificate, category: apple),
        Entry(pattern: "swscan.apple.com", title: appleSoftwareUpdate, category: apple),
        Entry(pattern: "swdist.apple.com", title: appleSoftwareUpdate, category: apple),
        Entry(pattern: "mesu.apple.com", title: appleSoftwareUpdate, category: apple),
        Entry(pattern: "safebrowsing.apple.com", title: appleSafeBrowsing, category: apple),
        Entry(pattern: "captive.apple.com", title: appleCaptiveCheck, category: apple),
        Entry(pattern: ".apple.com", title: appleService, category: apple),
        Entry(pattern: ".googleapis.com", title: googleAPIs, category: cloud),
        Entry(pattern: ".google.com", title: google, category: cloud),
        Entry(pattern: ".gstatic.com", title: googleStatic, category: cloud),
        Entry(pattern: ".googlevideo.com", title: youTube, category: media),
        Entry(pattern: ".youtube.com", title: youTube, category: media),
        Entry(pattern: ".cloudflare.com", title: cloudflare, category: cloud),
        Entry(pattern: ".amazonaws.com", title: aws, category: cloud),
        Entry(pattern: ".cloudfront.net", title: cloudFront, category: cdn),
        Entry(pattern: ".akamaized.net", title: akamai, category: cdn),
        Entry(pattern: ".edgekey.net", title: akamai, category: cdn),
        Entry(pattern: ".fastly.net", title: fastly, category: cdn),
        Entry(pattern: ".github.com", title: gitHub, category: developer),
        Entry(pattern: ".githubusercontent.com", title: gitHub, category: developer),
        Entry(pattern: ".dropbox.com", title: dropbox, category: productivity),
        Entry(pattern: ".dropboxusercontent.com", title: dropbox, category: productivity),
        Entry(pattern: ".slack.com", title: slack, category: productivity),
        Entry(pattern: ".slack-edge.com", title: slack, category: productivity),
        Entry(pattern: ".spotify.com", title: spotify, category: media),
        Entry(pattern: ".scdn.co", title: spotify, category: media),
        Entry(pattern: ".netflix.com", title: netflix, category: media),
        Entry(pattern: ".nflxvideo.net", title: netflix, category: media),
        Entry(pattern: ".zoom.us", title: zoom, category: productivity),
        Entry(pattern: ".microsoft.com", title: microsoft365, category: productivity),
        Entry(pattern: ".office.net", title: microsoft365, category: productivity),
        Entry(pattern: ".mozilla.org", title: mozilla, category: developer),
        Entry(pattern: ".local", title: localDevice, category: localNetwork),
        Entry(pattern: "localhost", title: thisMac, category: localNetwork),
        Entry(pattern: "1.1.1.1", title: cloudflareDNS, category: network),
        Entry(pattern: "8.8.8.8", title: googleDNS, category: network),
        Entry(pattern: "9.9.9.9", title: quad9DNS, category: network),
    ]

    // MARK: - Processes

    private static let processEntries: [Entry] = [
        Entry(pattern: "mdnsresponder", title: bonjour, category: localNetwork),
        Entry(pattern: "mdnsresponderhelper", title: bonjour, category: localNetwork),
        Entry(pattern: "identitys", title: appleIdentity, category: apple),
        Entry(pattern: "apsd", title: applePushDaemon, category: apple),
        Entry(pattern: "cloudd", title: iCloudDaemon, category: apple),
        Entry(pattern: "nsurlsessiond", title: backgroundDownloads, category: apple),
        Entry(pattern: "sharingd", title: airDrop, category: apple),
        Entry(pattern: "rapportd", title: continuity, category: apple),
        Entry(pattern: "com.apple.webkit", title: webContent, category: browsing),
        Entry(pattern: "safari", title: safari, category: browsing),
        Entry(pattern: "google chrome", title: chrome, category: browsing),
        Entry(pattern: "firefox", title: firefox, category: browsing),
        Entry(pattern: "node", title: nodeJS, category: developer),
        Entry(pattern: "python", title: python, category: developer),
        Entry(pattern: "docker", title: docker, category: developer),
        Entry(pattern: "ssh", title: ssh, category: network),
        Entry(pattern: "backupd", title: timeMachine, category: apple),
        Entry(pattern: "lsof", title: lanFiScan, category: localNetwork),
    ]

    // MARK: - Lookup

    /// `www.Example.COM.:443` → `example.com`.
    static func normalizedHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let colon = host.lastIndex(of: ":"), !host.contains("]") {
            // Drop a port, but leave a bare IPv6 address alone.
            let candidate = String(host[..<colon])
            if Int(host[host.index(after: colon)...]) != nil { host = candidate }
        }
        while host.hasPrefix("www.") { host.removeFirst(4) }
        while host.hasSuffix(".") { host.removeLast() }
        return host
    }

    static func describe(domain raw: String) -> ServiceDescription? {
        let host = normalizedHost(raw)
        guard !host.isEmpty else { return nil }

        var best: Entry?
        for entry in domainEntries where matches(host: host, pattern: entry.pattern) {
            if best == nil || entry.pattern.count > best!.pattern.count { best = entry }
        }
        guard let best else { return nil }
        return ServiceDescription(title: best.title, category: best.category, source: .bundled)
    }

    static func describe(process raw: String) -> ServiceDescription? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }

        var best: Entry?
        for entry in processEntries where name == entry.pattern || name.contains(entry.pattern) {
            if best == nil || entry.pattern.count > best!.pattern.count { best = entry }
        }
        guard let best else { return nil }
        return ServiceDescription(title: best.title, category: best.category, source: .bundled)
    }

    private static func matches(host: String, pattern: String) -> Bool {
        pattern.hasPrefix(".") ? host == String(pattern.dropFirst()) || host.hasSuffix(pattern) : host == pattern
    }

    // MARK: - Shared titles

    private static let apple = String(localized: "Apple")
    private static let cloud = String(localized: "Cloud")
    private static let cdn = String(localized: "CDN")
    private static let developer = String(localized: "Developer")
    private static let media = String(localized: "Media")
    private static let productivity = String(localized: "Productivity")
    private static let browsing = String(localized: "Browsing")
    private static let network = String(localized: "Network")
    private static let localNetwork = String(localized: "Local network")

    private static let appleService = String(localized: "Apple service")
    private static let applePush = String(localized: "Apple push notifications")
    private static let appleTime = String(localized: "Apple time synchronization")
    private static let appleCertificate = String(localized: "Apple certificate status check")
    private static let appleSoftwareUpdate = String(localized: "Apple software update")
    private static let appleSafeBrowsing = String(localized: "Apple Safe Browsing lookup")
    private static let appleCaptiveCheck = String(localized: "Apple captive-portal check")
    private static let iCloud = String(localized: "Apple iCloud sync")
    private static let appleIdentity = String(localized: "Apple identity and device services")
    private static let applePushDaemon = String(localized: "Apple push notifications daemon")
    private static let iCloudDaemon = String(localized: "iCloud sync daemon")
    private static let backgroundDownloads = String(localized: "Background downloads for apps")
    private static let airDrop = String(localized: "AirDrop and Handoff")
    private static let continuity = String(localized: "Apple Continuity")
    private static let google = String(localized: "Google service")
    private static let googleAPIs = String(localized: "Google APIs")
    private static let googleStatic = String(localized: "Google static assets")
    private static let googleDNS = String(localized: "Google public DNS")
    private static let youTube = String(localized: "YouTube video delivery")
    private static let cloudflare = String(localized: "Cloudflare edge")
    private static let cloudflareDNS = String(localized: "Cloudflare public DNS")
    private static let quad9DNS = String(localized: "Quad9 public DNS")
    private static let aws = String(localized: "Amazon Web Services")
    private static let cloudFront = String(localized: "Amazon CloudFront CDN")
    private static let akamai = String(localized: "Akamai CDN")
    private static let fastly = String(localized: "Fastly CDN")
    private static let gitHub = String(localized: "GitHub")
    private static let dropbox = String(localized: "Dropbox sync")
    private static let slack = String(localized: "Slack")
    private static let spotify = String(localized: "Spotify")
    private static let netflix = String(localized: "Netflix streaming")
    private static let zoom = String(localized: "Zoom meetings")
    private static let microsoft365 = String(localized: "Microsoft 365")
    private static let mozilla = String(localized: "Mozilla services")
    private static let localDevice = String(localized: "Local network device (Bonjour)")
    private static let thisMac = String(localized: "This Mac")
    private static let bonjour = String(localized: "Bonjour / mDNS discovery")
    private static let safari = String(localized: "Safari web content")
    private static let webContent = String(localized: "Web content hosted by an app")
    private static let chrome = String(localized: "Google Chrome")
    private static let firefox = String(localized: "Firefox")
    private static let nodeJS = String(localized: "Node.js process")
    private static let python = String(localized: "Python script or server")
    private static let docker = String(localized: "Docker containers")
    private static let ssh = String(localized: "SSH session")
    private static let timeMachine = String(localized: "Time Machine backup")
    private static let lanFiScan = String(localized: "LanFi socket scan")
}
