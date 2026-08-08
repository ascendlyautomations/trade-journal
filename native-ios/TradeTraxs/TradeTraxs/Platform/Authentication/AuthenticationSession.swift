import Foundation

nonisolated enum AuthenticationProviderKind: String, Codable, Sendable, CaseIterable {
    case email
    case apple
    case google
    case oauth
    case development
    case passkey
}

/// Persisted authenticated session (tokens stored via TokenStore / Keychain).
nonisolated struct AuthenticationSession: Codable, Sendable, Equatable {
    var userID: UserID
    var email: String?
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var provider: AuthenticationProviderKind
    var createdAt: Date
    var lastRefreshedAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    func isExpired(leeway: TimeInterval) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(leeway) >= expiresAt
    }
}
