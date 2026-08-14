import Foundation

/// Logical API lane for multi-backend routing.
nonisolated enum APIEnvironment: String, Sendable, CaseIterable, Codable {
    case debug
    case staging
    case production

    static func from(build: BuildConfiguration) -> APIEnvironment {
        switch build {
        case .debug: return .debug
        case .staging: return .staging
        case .production: return .production
        }
    }
}

/// Hosts for the two primary transports (Supabase + BFF) plus future externals.
nonisolated struct EnvironmentConfiguration: Sendable, Equatable {
    let apiEnvironment: APIEnvironment

    /// Next.js BFF origin (Debug → ios-app preview; Release → www.tradetraxs.com).
    let bffBaseURL: URL?

    /// Supabase project URL (Auth / REST / Storage / Functions host).
    let supabaseURL: URL?

    /// Public Supabase anon key used as `apikey` on Supabase hosts.
    let supabaseAnonKey: String?

    /// Optional future third-party API root.
    let externalAPIBaseURL: URL?

    /// Default request timeout for ordinary calls.
    let requestTimeout: TimeInterval

    /// Resource timeout for large uploads/downloads.
    let resourceTimeout: TimeInterval

    /// Max concurrent connections hint for URLSession.
    let httpMaximumConnectionsPerHost: Int

    /// Whether waitsForConnectivity is enabled.
    let waitsForConnectivity: Bool

    var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey?.isEmpty == false
    }

    static func make(
        for build: BuildConfiguration,
        appConfiguration: AppConfiguration
    ) -> EnvironmentConfiguration {
        EnvironmentConfiguration(
            apiEnvironment: .from(build: build),
            bffBaseURL: appConfiguration.apiBaseURL,
            supabaseURL: appConfiguration.supabaseURL,
            supabaseAnonKey: appConfiguration.supabaseAnonKey,
            externalAPIBaseURL: nil,
            requestTimeout: 30,
            resourceTimeout: 300,
            httpMaximumConnectionsPerHost: 6,
            waitsForConnectivity: true
        )
    }
}
