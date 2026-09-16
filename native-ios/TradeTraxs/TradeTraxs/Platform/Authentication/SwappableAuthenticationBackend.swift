import Foundation
import OSLog
import os

/// Allows installing the live Supabase backend after logged-out shell bootstrap.
final class SwappableAuthenticationBackend: AuthenticationBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var backend: any AuthenticationBackend

    init(initial: any AuthenticationBackend) {
        self.backend = initial
    }

    func install(_ backend: any AuthenticationBackend) {
        lock.lock()
        self.backend = backend
        let installedType = String(describing: type(of: backend))
        lock.unlock()
#if DEBUG
        AppLog.authentication.debug(
            "[AppleAuth] swappable.install backend=\(installedType, privacy: .public) swappable=\(ObjectIdentifier(self).debugDescription, privacy: .public)"
        )
#endif
    }

    private func current() -> any AuthenticationBackend {
        lock.lock()
        defer { lock.unlock() }
        return backend
    }

    func signIn(email: String, password: String) async throws -> AuthenticationSession {
        try await current().signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws -> AuthenticationSession {
        try await current().signUp(email: email, password: password)
    }

    func signOut(accessToken: String) async throws {
        try await current().signOut(accessToken: accessToken)
    }

    func refresh(refreshToken: String) async throws -> AuthenticationSession {
        try await current().refresh(refreshToken: refreshToken)
    }

    func requestPasswordReset(email: String) async throws {
        try await current().requestPasswordReset(email: email)
    }

    func resendSignupConfirmation(email: String) async throws {
        try await current().resendSignupConfirmation(email: email)
    }

    func updateUserMetadata(accessToken: String, metadata: [String: String]) async throws {
        try await current().updateUserMetadata(accessToken: accessToken, metadata: metadata)
    }

    func signInWithIDToken(
        provider: AuthenticationProviderKind,
        idToken: String,
        nonce: String?
    ) async throws -> AuthenticationSession {
        let active = current()
#if DEBUG
        AppLog.authentication.debug(
            "[AppleAuth] idTokenExchange.forward provider=\(provider.rawValue, privacy: .public) activeBackend=\(String(describing: type(of: active)), privacy: .public) swappable=\(ObjectIdentifier(self).debugDescription, privacy: .public)"
        )
#endif
        do {
            let session = try await active.signInWithIDToken(
                provider: provider,
                idToken: idToken,
                nonce: nonce
            )
#if DEBUG
            AppLog.authentication.debug("[AppleAuth] idTokenExchange.succeeded provider=\(provider.rawValue, privacy: .public)")
#endif
            return session
        } catch {
#if DEBUG
            AppLog.authentication.debug(
                "[AppleAuth] idTokenExchange.failed errorType=\(String(describing: type(of: error)), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
#endif
            throw error
        }
    }
}

/// Defers Google OAuth wiring until networking exists (logged-out fast launch).
final class SwappableGoogleSignInPerformer: GoogleSignInPerforming, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<(any GoogleSignInPerforming)?>(initialState: nil)

    init(fallback: any GoogleSignInPerforming) {
        lock.withLock { $0 = fallback }
    }

    func install(_ performer: any GoogleSignInPerforming) {
        lock.withLock { $0 = performer }
    }

    func signIn() async throws -> AuthenticationSession {
        guard let active = lock.withLock({ $0 }) else {
            throw AuthenticationError.notConfigured
        }
        return try await active.signIn()
    }
}
