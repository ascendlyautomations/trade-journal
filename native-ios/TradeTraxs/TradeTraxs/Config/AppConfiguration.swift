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

    static func make(
        for buildConfiguration: BuildConfiguration = .current,
        secrets: SecretsLoader.Values = SecretsLoader.load()
    ) -> AppConfiguration {
        AppConfiguration(
            buildConfiguration: buildConfiguration,
            apiBaseURL: secrets.apiBaseURL,
            supabaseURL: secrets.supabaseURL,
            supabaseAnonKey: secrets.supabaseAnonKey,
            appDisplayName: "TradeTraxs"
        )
    }
}
