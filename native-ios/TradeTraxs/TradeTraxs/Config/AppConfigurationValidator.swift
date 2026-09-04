import Foundation
import OSLog

/// Startup validation for public client configuration — never logs credentials.
nonisolated enum AppConfigurationValidator {
    enum APIBaseKind: String, Sendable {
        case production
        case custom
        case missing
    }

    struct Report: Sendable {
        let buildConfiguration: BuildConfiguration
        let isSupabaseConfigured: Bool
        let apiBaseKind: APIBaseKind
        let backendV2Flags: [(name: String, enabled: Bool)]
    }

    static func validate(_ configuration: AppConfiguration) -> Report {
        Report(
            buildConfiguration: configuration.buildConfiguration,
            isSupabaseConfigured: configuration.isSupabaseConfigured,
            apiBaseKind: apiBaseKind(for: configuration.apiBaseURL),
            backendV2Flags: BackendV2FeatureFlag.allCases.map {
                ($0.rawValue, BackendV2FeatureFlags.isEnabled($0))
            }
        )
    }

    /// Logs a sanitized summary and fails Release builds that lack Supabase client config.
    static func assertReadyForLaunch(_ configuration: AppConfiguration) {
        let report = validate(configuration)
        logSanitized(report)

        guard configuration.buildConfiguration == .production else { return }
        guard report.isSupabaseConfigured else {
            fatalError(
                """
                Release build is missing Supabase client configuration. \
                Add TradeTraxs/Config/Secrets.plist or TradeTraxs/Config/Secrets.production.plist before archiving.
                """
            )
        }
    }

    private static func apiBaseKind(for url: URL?) -> APIBaseKind {
        guard let url else { return .missing }
        return normalizedOrigin(url) == normalizedOrigin(AppConfiguration.productionBFFBaseURL)
            ? .production
            : .custom
    }

    private static func normalizedOrigin(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return (components?.string ?? url.absoluteString)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func logSanitized(_ report: Report) {
        let logger = Logger(subsystem: AppLog.subsystem, category: "Configuration")
        logger.info(
            "Build lane: \(report.buildConfiguration.displayName, privacy: .public)"
        )
        logger.info(
            "Supabase configured: \(report.isSupabaseConfigured, privacy: .public)"
        )
        logger.info(
            "API base: \(report.apiBaseKind.rawValue, privacy: .public)"
        )
        for entry in report.backendV2Flags {
            logger.info(
                "BackendV2.\(entry.name, privacy: .public): \(entry.enabled ? "enabled" : "disabled", privacy: .public)"
            )
        }
    }
}
