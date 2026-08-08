import Foundation

/// Google Sign In → Supabase `id_token` exchange.
///
/// Presentation / Google SDK UI arrives with Auth screens. This provider accepts an
/// injectable credential source so the Authentication Platform stays UI-agnostic.
nonisolated struct GoogleSignInProvider: OAuthProviding {
    let kind: AuthenticationProviderKind = .google
    private let backend: any AuthenticationBackend
    private let credentialSource: any GoogleCredentialProviding

    init(
        backend: any AuthenticationBackend,
        credentialSource: any GoogleCredentialProviding = UnavailableGoogleCredentialSource()
    ) {
        self.backend = backend
        self.credentialSource = credentialSource
    }

    func signIn() async throws -> AuthenticationSession {
        let credential = try await credentialSource.requestCredential()
        return try await backend.signInWithIDToken(
            provider: .google,
            idToken: credential.idToken,
            nonce: credential.nonce
        )
    }

    func signOut(session: AuthenticationSession) async throws {
        try await backend.signOut(accessToken: session.accessToken)
    }
}

nonisolated struct GoogleIDCredentialPayload: Sendable {
    var idToken: String
    var nonce: String?
}

nonisolated protocol GoogleCredentialProviding: Sendable {
    func requestCredential() async throws -> GoogleIDCredentialPayload
}

/// Placeholder until Google Sign-In SDK / Auth UI presentation is wired.
nonisolated struct UnavailableGoogleCredentialSource: GoogleCredentialProviding {
    func requestCredential() async throws -> GoogleIDCredentialPayload {
        throw AuthenticationError.providerUnavailable(.google)
    }
}

/// Test / future UI adapter that supplies a ready ID token.
nonisolated struct StaticGoogleCredentialSource: GoogleCredentialProviding {
    let payload: GoogleIDCredentialPayload

    func requestCredential() async throws -> GoogleIDCredentialPayload {
        payload
    }
}
