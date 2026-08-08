import Foundation

nonisolated struct EmailAuthenticationProvider: AuthenticationProviding {
    let kind: AuthenticationProviderKind = .email
    private let backend: any AuthenticationBackend
    private let validator: AuthenticationValidator

    init(
        backend: any AuthenticationBackend = PlaceholderAuthenticationBackend(),
        validator: AuthenticationValidator = AuthenticationValidator()
    ) {
        self.backend = backend
        self.validator = validator
    }

    func signIn(email: String, password: String) async throws -> AuthenticationSession {
        if let error = validator.validateSignIn(email: email, password: password) { throw error }
        return try await backend.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws -> AuthenticationSession {
        if let error = validator.validateSignIn(email: email, password: password) { throw error }
        if let passwordError = validator.validatePassword(password) { throw passwordError }
        return try await backend.signUp(email: email, password: password)
    }

    func signOut(session: AuthenticationSession) async throws {
        try await backend.signOut(accessToken: session.accessToken)
    }

    func refresh(session: AuthenticationSession) async throws -> AuthenticationSession {
        guard let refreshToken = session.refreshToken else {
            throw AuthenticationError.refreshFailed
        }
        return try await backend.refresh(refreshToken: refreshToken)
    }

    func requestPasswordReset(email: String) async throws {
        if let error = validator.validateEmail(email) { throw error }
        try await backend.requestPasswordReset(email: email)
    }
}
