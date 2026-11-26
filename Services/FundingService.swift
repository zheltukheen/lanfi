import Foundation
import LanFiCore

/// The support list ships inside the app. `project.yml` copies the repository's
/// `.github/FUNDING.yml` into the bundle at build time, so GitHub's Sponsor
/// button and this sheet read the same file and nothing is downloaded at run
/// time.
enum FundingService {
    static func options(bundle: Bundle = .main) -> [FundingOption] {
        guard
            let url =
                bundle.url(forResource: "FUNDING", withExtension: "yml")
                ?? bundle.url(forResource: "FUNDING", withExtension: "yaml"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return fallback }

        let options = FundingCatalog.parse(text)
        return options.isEmpty ? fallback : options
    }

    /// The same destination as FUNDING.yml, used only if a broken build ships
    /// without the file.
    static let fallback: [FundingOption] = [
        FundingCatalog.option(platform: "custom", value: "https://boosty.to/zheltukheen")
    ].compactMap { $0 }
}
