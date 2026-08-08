import Foundation

/// Secure logout: remote revoke (best effort) → destroy credentials → memory cleanup.
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

    func logout() async {
        let session = sessionManager.currentSession
        if let session {
            try? await emailProvider.signOut(session: session)
        }
        try? sessionManager.destroy()
        try? credentials.clearAll()
        sessionManager.clearMemory()
    }
}
