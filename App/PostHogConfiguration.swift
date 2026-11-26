import Foundation
import PostHog

enum PostHogConfiguration {
    static func setup() {
        guard let projectToken = configuredValue(for: "POSTHOG_PROJECT_TOKEN") else {
            reportMissingConfiguration("POSTHOG_PROJECT_TOKEN")
            return
        }

        guard let host = configuredValue(for: "POSTHOG_HOST") else {
            reportMissingConfiguration("POSTHOG_HOST")
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        config.logs.serviceName = "lanfi-macos"
        #if DEBUG
            config.logs.environment = "development"
        #else
            config.logs.environment = "production"
        #endif
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.logger?.info("PostHog log capture configured")
    }

    private static func configuredValue(for key: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[key]
        let bundledValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let value = environmentValue ?? bundledValue
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }

    private static func reportMissingConfiguration(_ key: String) {
        #if DEBUG
            preconditionFailure(
                "\(key) variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once \(key) is configured"
            )
        #endif
    }
}
