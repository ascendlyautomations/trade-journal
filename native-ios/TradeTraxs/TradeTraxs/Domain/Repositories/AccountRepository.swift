import Foundation

/// Self-service account deletion — server determines the target user from the session token.
nonisolated protocol AccountRepository: Sendable {
    func deleteAuthenticatedAccount() async throws
}

enum AccountDeletionError: Error, Equatable, Sendable {
    case notAuthenticated
    case serverMessage(String)
}
