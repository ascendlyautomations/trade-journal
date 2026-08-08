import Foundation

nonisolated struct SessionExpiration: Sendable {
    var leeway: TimeInterval

    init(leeway: TimeInterval = 60) {
        self.leeway = leeway
    }

    func isExpired(_ session: AuthenticationSession) -> Bool {
        session.isExpired(leeway: leeway)
    }

    func needsRefresh(_ session: AuthenticationSession) -> Bool {
        guard session.refreshToken != nil else { return false }
        return session.isExpired(leeway: leeway)
    }

    func timeUntilRefresh(for session: AuthenticationSession) -> TimeInterval? {
        guard let expiresAt = session.expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSinceNow - leeway)
    }
}
