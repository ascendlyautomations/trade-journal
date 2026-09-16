import Foundation

/// Secure logout: local teardown first; remote revoke is best-effort and never blocks UI.
final class LogoutCoordinator: Sendable {
    private let sessionManager: SessionManager
    private let emailProvider: any AuthenticationProviding
    private let credentials: any SecureCredentialStoring

    init(
        sessionManager: SessionManager,
        emailProvider: any AuthenticationProviding,
        credentials: any SecureCredentialStoring
    ) {
        self.sessionManager = sessionManager
        self.emailProvider = emailProvider
        self.credentials = credentials
    }

    /// Authoritative local sign-out — synchronous credential/session destruction.
    func performLocalTeardown() -> AuthenticationSession? {
        let session = sessionManager.currentSession
        try? sessionManager.destroy()
        try? credentials.clearAll()
        sessionManager.clearMemory()
        return session
    }

    /// Best-effort remote revoke — must not block local logout completion.
    func signOutRemotely(session: AuthenticationSession) async {
        try? await emailProvider.signOut(session: session)
    }
}
