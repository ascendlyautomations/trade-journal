import Foundation

/// Generic OAuth provider shell for future social logins.
nonisolated struct OAuthProvider: OAuthProviding {
    let kind: AuthenticationProviderKind

    func signIn() async throws -> AuthenticationSession {
        throw AuthenticationError.providerUnavailable(kind)
    }

    func signOut(session: AuthenticationSession) async throws {
        _ = session
    }
}
