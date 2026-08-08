import Foundation

/// Future Passkey / WebAuthn surface — architecture reserved, not implemented.
nonisolated protocol PasskeyAuthenticating: Sendable {
    var isSupported: Bool { get }
    func signIn() async throws -> AuthenticationSession
    func register() async throws
}

nonisolated struct FuturePasskeySupport: PasskeyAuthenticating {
    var isSupported: Bool { false }

    func signIn() async throws -> AuthenticationSession {
        throw AuthenticationError.providerUnavailable(.passkey)
    }

    func register() async throws {
        throw AuthenticationError.providerUnavailable(.passkey)
    }
}
