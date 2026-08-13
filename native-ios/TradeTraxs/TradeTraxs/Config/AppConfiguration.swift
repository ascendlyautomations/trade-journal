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

    /// Production Next.js BFF origin used when ``API_BASE_URL`` is unset.
    /// Local Next.js: set Secrets.plist / env `API_BASE_URL` to `http://localhost:3000`.
    static let defaultBFFBaseURL = URL(string: "https://www.tradetraxs.com")!

    static func make(
        for buildConfiguration: BuildConfiguration = .current,
        secrets: SecretsLoader.Values = SecretsLoader.load()
    ) -> AppConfiguration {
        AppConfiguration(
            buildConfiguration: buildConfiguration,
            apiBaseURL: secrets.apiBaseURL ?? Self.defaultBFFBaseURL,
            supabaseURL: secrets.supabaseURL,
            supabaseAnonKey: secrets.supabaseAnonKey,
            appDisplayName: "TradeTraxs"
        )
    }
}
