import Foundation

/// In-memory + durable session owner used by networking and auth flows.
final class SessionManager: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AuthenticationSession?
    private let store: any SessionStoring
    private let expiration: SessionExpiration

    init(store: any SessionStoring, expiration: SessionExpiration) {
        self.store = store
        self.expiration = expiration
    }

    var currentSession: AuthenticationSession? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    var accessToken: String? {
        currentSession?.accessToken
    }

    var currentUserID: UserID? {
        currentSession?.userID
    }

    func install(_ session: AuthenticationSession) throws {
        try store.save(session)
        lock.lock(); current = session; lock.unlock()
    }

    func updateTokens(accessToken: String, refreshToken: String?, expiresAt: Date?) throws {
        lock.lock()
        guard var session = current else {
            lock.unlock()
            throw AuthenticationError.sessionMissing
        }
        session.accessToken = accessToken
        if let refreshToken { session.refreshToken = refreshToken }
        session.expiresAt = expiresAt
        session.lastRefreshedAt = Date()
        current = session
        lock.unlock()
        try store.save(session)
    }

    func restoreFromStore() throws -> AuthenticationSession? {
        let restoration = SessionRestoration(store: store, expiration: expiration)
        let session = try restoration.restore()
        lock.lock(); current = session; lock.unlock()
        return session
    }

    func destroy() throws {
        try store.destroy()
        lock.lock(); current = nil; lock.unlock()
    }

    func clearMemory() {
        lock.lock(); current = nil; lock.unlock()
    }
}

/// Bridges Platform auth session into Data ``SessionProviding``.
nonisolated struct AuthenticationSessionBridge: SessionProviding {
    private let sessionManager: SessionManager

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    var currentUserID: UserID? {
        get async { sessionManager.currentUserID }
    }

    var accessToken: String? {
        get async { sessionManager.accessToken }
    }
}
