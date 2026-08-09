import Foundation

nonisolated protocol GoogleSignInPerforming: Sendable {
    func signIn() async throws -> AuthenticationSession
}

/// Google Sign In → Supabase session.
nonisolated struct GoogleSignInProvider: OAuthProviding {
    let kind: AuthenticationProviderKind = .google
    private let performer: any GoogleSignInPerforming

    init(performer: any GoogleSignInPerforming) {
        self.performer = performer
    }

    func signIn() async throws -> AuthenticationSession {
        try await performer.signIn()
    }

    func signOut(session: AuthenticationSession) async throws {
        _ = session
    }
}

/// ID-token exchange path (tests / future Google SDK).
nonisolated struct GoogleIDTokenSignInPerformer: GoogleSignInPerforming {
    private let backend: any AuthenticationBackend
    private let credentialSource: any GoogleCredentialProviding

    init(
        backend: any AuthenticationBackend,
        credentialSource: any GoogleCredentialProviding
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
}

nonisolated struct GoogleIDCredentialPayload: Sendable {
    var idToken: String
    var nonce: String?
}

nonisolated protocol GoogleCredentialProviding: Sendable {
    func requestCredential() async throws -> GoogleIDCredentialPayload
}

nonisolated struct UnavailableGoogleCredentialSource: GoogleCredentialProviding {
    func requestCredential() async throws -> GoogleIDCredentialPayload {
        throw AuthenticationError.providerUnavailable(.google)
    }
}

nonisolated struct StaticGoogleCredentialSource: GoogleCredentialProviding {
    let payload: GoogleIDCredentialPayload

    func requestCredential() async throws -> GoogleIDCredentialPayload {
        payload
    }
}
