import Foundation

/// Launch / runtime authentication knobs. No secrets live here.
nonisolated struct AuthenticationConfiguration: Sendable, Equatable {
    var keychainService: String
    var accessTokenAccount: String
    var refreshTokenAccount: String
    var sessionAccount: String
    var refreshLeeway: TimeInterval
    var allowsDevelopmentSessionBypass: Bool
    var biometricUnlockEnabled: Bool

    static func make(for build: BuildConfiguration) -> AuthenticationConfiguration {
        AuthenticationConfiguration(
            keychainService: Bundle.main.bundleIdentifier ?? "com.tradetraxs.ios",
            accessTokenAccount: "auth.accessToken",
            refreshTokenAccount: "auth.refreshToken",
            sessionAccount: "auth.session",
            refreshLeeway: 60,
            allowsDevelopmentSessionBypass: build == .debug,
            biometricUnlockEnabled: false
        )
    }
}
