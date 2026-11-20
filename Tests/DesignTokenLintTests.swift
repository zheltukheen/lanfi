import XCTest

/// A lint that a unit test can enforce: `Views/` may not hard-code a corner
/// radius or a translucent colour fill, because those numbers are what drifted
/// between the toolkit, the Wi-Fi workspace and Settings before `Theme` existed.
///
/// `Views/Theme.swift` is the one file allowed to name numbers — that is where
/// the tokens live. Anything else in `Views/` must go through `DesignToken`.
final class DesignTokenLintTests: XCTestCase {
    private static let tokenFile = "Theme.swift"

    /// A literal radius: `.cornerRadius(8)`. `Theme.Radius.card` and
    /// `DesignToken.Radius.badge` are fine, and so is Charts' own CGFloat use
    /// when it reads a token.
    private static let literalRadius = try! NSRegularExpression(
        pattern: #"\.cornerRadius\(\s*[0-9]"#)
    /// A translucent colour written as a literal: `Color.orange.opacity(0.08)`,
    /// `AppPalette.warning.opacity(0.08)`. A dynamic tint such as
    /// `color.opacity(0.06)` is not flagged: the colour comes from data, not
    /// from a role.
    private static let literalFill = try! NSRegularExpression(
        pattern: #"(Color\.[A-Za-z]+|AppPalette\.[A-Za-z]+)\.opacity\(\s*0\.0[0-9]"#)

    func testViewsUseRadiusTokens() throws {
        let offenders = try scan(Self.literalRadius)
        XCTAssertTrue(
            offenders.isEmpty,
            "Hard-coded corner radii in Views/ — use Theme.Radius (badge/control/card/sheet):\n"
                + offenders.joined(separator: "\n"))
    }

    func testViewsUseSurfaceTokensForTranslucentFills() throws {
        let offenders = try scan(Self.literalFill)
        XCTAssertTrue(
            offenders.isEmpty,
            "Hard-coded translucent fills in Views/ — use DesignToken.Surface (subtleFill, accentFill, warningFill, dangerFill, cardStroke):\n"
                + offenders.joined(separator: "\n"))
    }

    // MARK: - Scanning

    private func scan(_ expression: NSRegularExpression) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let views = root.appendingPathComponent("Views")
        let files = try FileManager.default.subpathsOfDirectory(atPath: views.path)
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix(Self.tokenFile) }
            .sorted()

        var offenders: [String] = []
        for file in files {
            let url = views.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if expression.firstMatch(in: line, range: range) != nil {
                    offenders.append("Views/\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return offenders
    }
}
