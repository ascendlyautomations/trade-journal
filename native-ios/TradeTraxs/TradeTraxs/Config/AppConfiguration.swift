import Foundation

/// Non-secret runtime configuration for the active ``BuildConfiguration``.
///
/// Public client values (Supabase URL / anon key / BFF URL) come from
/// ``SecretsLoader`` (Secrets.plist, Info.plist, or process environment).
/// Service-role keys must never be embedded in the iOS client.
struct AppConfiguration: Sendable, Equatable {
    let buildConfiguration: BuildConfiguration

    /// Public site / BFF origin.
    let apiBaseURL: URL?

    /// Public Supabase project URL.
    let supabaseURL: URL?

    /// Public Supabase anon (publishable) key.
    let supabaseAnonKey: String?

    /// Bundle-facing app display name.
    let appDisplayName: String

    var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey?.isEmpty == false
    }

    /// Default Next.js BFF when ``API_BASE_URL`` is unset (Debug, Staging, and Production).
    static let productionBFFBaseURL = URL(string: "https://www.tradetraxs.com")!

    /// Build-lane default BFF origin when ``API_BASE_URL`` is unset.
    /// Override anytime via Secrets.plist / env `API_BASE_URL` (e.g. `http://localhost:3000`).
    static func defaultBFFBaseURL(for buildConfiguration: BuildConfiguration) -> URL {
        switch buildConfiguration {
        case .debug, .staging, .production:
            return productionBFFBaseURL
        }
    }

    /// Backward-compatible alias for the default BFF origin.
    static var defaultBFFBaseURL: URL { productionBFFBaseURL }

    static func make(
        for buildConfiguration: BuildConfiguration = .current,
        secrets: SecretsLoader.Values = SecretsLoader.load()
    ) -> AppConfiguration {
        AppConfiguration(
            buildConfiguration: buildConfiguration,
            apiBaseURL: secrets.apiBaseURL ?? Self.defaultBFFBaseURL(for: buildConfiguration),
            supabaseURL: secrets.supabaseURL,
            supabaseAnonKey: secrets.supabaseAnonKey,
            appDisplayName: "TradeTraxs"
        )
    }
}
