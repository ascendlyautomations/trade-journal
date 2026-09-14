import Foundation
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
        lock.unlock()
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
