import Foundation

nonisolated struct SessionRestoration: Sendable {
    private let store: any SessionStoring
    private let expiration: SessionExpiration

    init(store: any SessionStoring, expiration: SessionExpiration) {
        self.store = store
        self.expiration = expiration
    }

    func restore() throws -> AuthenticationSession? {
        guard let session = try store.load() else { return nil }
        if expiration.isExpired(session), session.refreshToken == nil {
            try store.destroy()
            return nil
        }
        return session
    }
}
