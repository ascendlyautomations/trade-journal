import Foundation

/// Data-facing auth repository — delegates to ``AuthenticationManager``.
struct DefaultAuthenticationRepository: AuthenticationRepository, @unchecked Sendable {
    private let manager: AuthenticationManager

    init(manager: AuthenticationManager) {
        self.manager = manager
    }

    func currentSessionUserID() async throws -> UserID? {
        manager.state.session?.userID
    }

    func signIn(email: String, password: String) async throws -> User {
        try await manager.signIn(email: email, password: password)
        return try makeUser()
    }

    func signUp(email: String, password: String) async throws -> User {
        try await manager.signUp(email: email, password: password)
        return try makeUser()
    }

    func signOut() async throws {
        await manager.logout()
    }

    func requestPasswordReset(email: String) async throws {
        try await manager.requestPasswordReset(email: email)
    }

    private func makeUser() throws -> User {
        guard let session = manager.state.session else {
            throw AuthenticationError.sessionMissing
        }
        return User(
            id: session.userID,
            email: session.email,
            createdAt: session.createdAt
        )
    }
}
