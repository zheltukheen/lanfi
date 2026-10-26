import Foundation

/// Headless release validation. Run from a `.app` bundle:
///   LanFi.app/Contents/MacOS/LanFi --smoke-test
enum AppSmokeTest {
    static func run() -> Never {
        let bundle = Bundle.main
        var checks: [(String, Bool, String)] = []
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let bundleID = bundle.bundleIdentifier ?? "-"

        checks.append(("bundle-id", bundleID == "ru.zheltukheen.WiFA", bundleID))
        checks.append(("version", version != "-" && build != "-", "\(version) (\(build))"))
        checks.append(("oui-database", bundle.url(forResource: "oui", withExtension: nil) != nil, "oui"))
        checks.append(
            (
                "privacy-manifest", bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil,
                "PrivacyInfo.xcprivacy"
            ))
        checks.append(
            (
                "sparkle",
                bundle.privateFrameworksURL?.appendingPathComponent("Sparkle.framework").path.isEmpty == false
                    && FileManager.default.fileExists(
                        atPath: bundle.privateFrameworksURL?.appendingPathComponent("Sparkle.framework").path ?? ""
                    ),
                "Sparkle.framework"
            )
        )
        checks.append(("app-icon", bundle.url(forResource: "Assets", withExtension: "car") != nil, "Assets.car"))
        checks.append(("localization", bundle.path(forResource: "ru", ofType: "lproj") != nil, "ru.lproj"))
        checks.append(
            (
                "location-description", bundle.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil,
                "NSLocationUsageDescription"
            ))

        let failures = checks.filter { !$0.1 }
        let payload: [String: Any] = [
            "app": "LanFi",
            "version": version,
            "build": build,
            "bundleIdentifier": bundleID,
            "checks": checks.map { ["name": $0.0, "passed": $0.1, "detail": $0.2] },
            "ok": failures.isEmpty,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        {
            print(text)
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}
