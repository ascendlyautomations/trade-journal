import Foundation

/// Durable session persistence boundary.
nonisolated protocol SessionStoring: Sendable {
    func save(_ session: AuthenticationSession) throws
    func load() throws -> AuthenticationSession?
    func destroy() throws
}

nonisolated struct SessionStore: SessionStoring {
    private let credentials: any SecureCredentialStoring
    private let tokens: any TokenStoring

    init(credentials: any SecureCredentialStoring, tokens: any TokenStoring) {
        self.credentials = credentials
        self.tokens = tokens
    }

    func save(_ session: AuthenticationSession) throws {
        try credentials.saveSession(session)
        try tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken)
    }

    func load() throws -> AuthenticationSession? {
        try credentials.loadSession()
    }

    func destroy() throws {
        try credentials.clearSession()
        try tokens.clear()
    }
}
