import Foundation
import OSLog

#if DEBUG
/// DEBUG-only auth logging — never prints credentials, emails, or full session payloads.
nonisolated enum SafeAuthLog {
    private static let logger = AppLog.authentication

    struct Summary: Sendable {
        var authState: String
        var provider: AuthenticationProviderKind?
        var hasAccessToken: Bool
        var hasRefreshToken: Bool
        var tokenExpiryStatus: TokenExpiryStatus
        var correlationID: String

        enum TokenExpiryStatus: String, Sendable {
            case valid
            case nearExpiry
            case expired
            case unknown
        }
    }

    static func summary(
        for state: AuthenticationState,
        session: AuthenticationSession?,
        expiration: SessionExpiration,
        correlationID: String = AuthFlowTracer.beginCorrelation()
    ) -> Summary {
        let expiry: Summary.TokenExpiryStatus = {
            guard let session else { return .unknown }
            if expiration.isExpired(session) { return .expired }
            if expiration.needsRefresh(session) { return .nearExpiry }
            return .valid
        }()
        return Summary(
            authState: stateLabel(state),
            provider: session?.provider,
            hasAccessToken: session?.accessToken.isEmpty == false,
            hasRefreshToken: session?.refreshToken?.isEmpty == false,
            tokenExpiryStatus: expiry,
            correlationID: correlationID
        )
    }

    static func logState(_ state: AuthenticationState, session: AuthenticationSession?, expiration: SessionExpiration) {
        let summary = summary(for: state, session: session ?? state.session, expiration: expiration)
        log(summary)
    }

    static func logEvent(_ event: AuthenticationEvent, state: AuthenticationState) {
        logger.debug(
            "authEvent=\(eventName(event), privacy: .public) authState=\(stateLabel(state), privacy: .public)"
        )
    }

    static func log(_ summary: Summary) {
        let provider = summary.provider?.rawValue ?? "none"
        logger.debug(
            "authState=\(summary.authState, privacy: .public) provider=\(provider, privacy: .public) hasAccessToken=\(summary.hasAccessToken, privacy: .public) hasRefreshToken=\(summary.hasRefreshToken, privacy: .public) tokenExpiry=\(summary.tokenExpiryStatus.rawValue, privacy: .public) correlation=\(summary.correlationID, privacy: .public)"
        )
    }

    /// Returns true when `text` appears to contain credential material (for tests).
    static func containsCredentialLeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        let banned = [
            "bearer ",
            "authorization:",
            "access token",
            "refresh token",
            "access_token",
            "refresh_token",
            "user_metadata",
            "app_metadata",
            "eyj", // common JWT prefix
        ]
        if banned.contains(where: { lower.contains($0) }) { return true }
        if lower.contains("@") && lower.contains(".com") { return true }
        return false
    }

    private static func stateLabel(_ state: AuthenticationState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .unauthenticated: return "unauthenticated"
        case .authenticating(let kind): return "authenticating(\(kind.rawValue))"
        case .authenticated: return "authenticated"
        case .refreshing: return "refreshing"
        case .sessionValidationFailed: return "sessionValidationFailed"
        case .locked: return "locked"
        case .failure: return "failure"
        }
    }

    private static func eventName(_ event: AuthenticationEvent) -> String {
        switch event {
        case .restorationStarted: return "restorationStarted"
        case .restorationSucceeded: return "restorationSucceeded"
        case .restorationFailed: return "restorationFailed"
        case .signInStarted: return "signInStarted"
        case .signInSucceeded: return "signInSucceeded"
        case .signInFailed: return "signInFailed"
        case .tokenRefreshStarted: return "tokenRefreshStarted"
        case .tokenRefreshSucceeded: return "tokenRefreshSucceeded"
        case .tokenRefreshFailed: return "tokenRefreshFailed"
        case .sessionExpired: return "sessionExpired"
        case .logoutStarted: return "logoutStarted"
        case .logoutCompleted: return "logoutCompleted"
        case .biometricUnlockSucceeded: return "biometricUnlockSucceeded"
        case .biometricUnlockFailed: return "biometricUnlockFailed"
        }
    }
}
#else
nonisolated enum SafeAuthLog {
    struct Summary: Sendable {
        var authState: String = ""
        var provider: AuthenticationProviderKind?
        var hasAccessToken: Bool = false
        var hasRefreshToken: Bool = false
        var tokenExpiryStatus: Summary.TokenExpiryStatus = .unknown
        var correlationID: String = ""

        enum TokenExpiryStatus: String, Sendable {
            case valid, nearExpiry, expired, unknown
        }
    }

    static func logState(_ state: AuthenticationState, session: AuthenticationSession?, expiration: SessionExpiration) {}
    static func logEvent(_ event: AuthenticationEvent, state: AuthenticationState) {}
    static func log(_ summary: Summary) {}
    static func containsCredentialLeak(_ text: String) -> Bool { false }
}
#endif
