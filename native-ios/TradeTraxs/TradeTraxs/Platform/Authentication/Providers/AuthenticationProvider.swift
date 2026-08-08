import Foundation

/// Common auth provider contract — Supabase / OAuth implementations plug in later.
nonisolated protocol AuthenticationProviding: Sendable {
    var kind: AuthenticationProviderKind { get }
    func signIn(email: String, password: String) async throws -> AuthenticationSession
    func signUp(email: String, password: String) async throws -> AuthenticationSession
    func signOut(session: AuthenticationSession) async throws
    func refresh(session: AuthenticationSession) async throws -> AuthenticationSession
    func requestPasswordReset(email: String) async throws
}

nonisolated protocol OAuthProviding: Sendable {
    var kind: AuthenticationProviderKind { get }
    func signIn() async throws -> AuthenticationSession
    func signOut(session: AuthenticationSession) async throws
}

/// Future remote auth backend (Supabase Auth). Placeholder throws notConfigured.
nonisolated protocol AuthenticationBackend: Sendable {
    func signIn(email: String, password: String) async throws -> AuthenticationSession
    func signUp(email: String, password: String) async throws -> AuthenticationSession
    func signOut(accessToken: String) async throws
    func refresh(refreshToken: String) async throws -> AuthenticationSession
    func requestPasswordReset(email: String) async throws
}

nonisolated struct PlaceholderAuthenticationBackend: AuthenticationBackend {
    func signIn(email: String, password: String) async throws -> AuthenticationSession {
        _ = (email, password)
        throw AuthenticationError.notConfigured
    }

    func signUp(email: String, password: String) async throws -> AuthenticationSession {
        _ = (email, password)
        throw AuthenticationError.notConfigured
    }

    func signOut(accessToken: String) async throws {
        _ = accessToken
    }

    func refresh(refreshToken: String) async throws -> AuthenticationSession {
        _ = refreshToken
        throw AuthenticationError.notConfigured
    }

    func requestPasswordReset(email: String) async throws {
        _ = email
        throw AuthenticationError.notConfigured
    }
}

/// Test-only backend that issues real in-memory sessions (no network).
nonisolated struct InMemoryAuthenticationBackend: AuthenticationBackend {
    var defaultExpiresIn: TimeInterval = 3600

    func signIn(email: String, password: String) async throws -> AuthenticationSession {
        guard !email.isEmpty, !password.isEmpty else { throw AuthenticationError.invalidCredentials }
        return makeSession(email: email, provider: .email)
    }

    func signUp(email: String, password: String) async throws -> AuthenticationSession {
        try await signIn(email: email, password: password)
    }

    func signOut(accessToken: String) async throws {
        _ = accessToken
    }

    func refresh(refreshToken: String) async throws -> AuthenticationSession {
        guard !refreshToken.isEmpty else { throw AuthenticationError.refreshFailed }
        return makeSession(email: nil, provider: .email, refreshToken: refreshToken)
    }

    func requestPasswordReset(email: String) async throws {
        if email.isEmpty { throw AuthenticationError.invalidEmail }
    }

    private func makeSession(
        email: String?,
        provider: AuthenticationProviderKind,
        refreshToken: String = "refresh.\(UUID().uuidString)"
    ) -> AuthenticationSession {
        AuthenticationSession(
            userID: UserID(UUID().uuidString),
            email: email,
            accessToken: "access.\(UUID().uuidString)",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(defaultExpiresIn),
            provider: provider,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
    }
}
