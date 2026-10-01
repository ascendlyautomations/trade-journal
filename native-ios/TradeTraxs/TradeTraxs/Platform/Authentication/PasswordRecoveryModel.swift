import Foundation
import Observation

/// In-memory handoff from a reset Universal Link to the set-password screen.
/// The recovery code stays here only until exchange starts.
@MainActor
@Observable
final class PasswordRecoveryInbox {
    static let shared = PasswordRecoveryInbox()

    private(set) var generation: UInt64 = 0
    private var link: PasswordRecoveryLink?

    func receive(_ link: PasswordRecoveryLink) {
        self.link = link
        generation &+= 1
    }

    func take() -> PasswordRecoveryLink? {
        let current = link
        link = nil
        return current
    }

    func resetForTesting() {
        link = nil
        generation = 0
    }
}

nonisolated protocol PasswordRecoveryClient: Sendable {
    func exchangePKCE(code: String, verifier: String) async throws -> AuthenticationSession
    func verifyTokenHash(_ tokenHash: String) async throws -> AuthenticationSession
    func updatePassword(accessToken: String, newPassword: String) async throws
}

/// Exchanges a recovery link, then updates the existing user's password.
@MainActor
@Observable
final class PasswordRecoveryModel {
    static let shared = PasswordRecoveryModel()

    enum Phase: Equatable {
        case hidden
        case verifying
        case ready
        case invalid(String)
        case success(signedIn: Bool)
    }

    private(set) var phase: Phase = .hidden
    private(set) var isSaving = false
    var formError: String?

    var isPresented: Bool {
        if case .hidden = phase { return false }
        return true
    }

    private var client: (any PasswordRecoveryClient)?
    private var adoptSession: (@MainActor (AuthenticationSession) async throws -> Void)?
    private var recoverySession: AuthenticationSession?
    private var verifyTask: Task<Void, Never>?
    private var attempt: UInt64 = 0

    func configure(
        client: any PasswordRecoveryClient,
        adoptSession: @escaping @MainActor (AuthenticationSession) async throws -> Void
    ) {
        self.client = client
        self.adoptSession = adoptSession
    }

    func consumeInbox() {
        guard let link = PasswordRecoveryInbox.shared.take() else { return }
        begin(link)
    }

    func begin(_ link: PasswordRecoveryLink) {
        verifyTask?.cancel()
        recoverySession = nil
        formError = nil
        isSaving = false
        attempt &+= 1
        let current = attempt
        phase = .verifying
        verifyTask = Task { [weak self] in
            await self?.resolve(link, attempt: current)
        }
    }

    func save(password: String, confirmation: String) async {
        guard !isSaving else { return }
        if let message = PasswordRecoveryLink.validationMessage(password: password, confirmation: confirmation) {
            formError = message
            return
        }
        guard let session = recoverySession, let client else {
            phase = .invalid(PasswordRecoveryLink.invalidMessage)
            return
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }
        do {
            try await client.updatePassword(accessToken: session.accessToken, newPassword: password)
            var signedIn = false
            if let adoptSession {
                do {
                    try await adoptSession(session)
                    signedIn = true
                } catch {
                    signedIn = false
                }
            }
            recoverySession = nil
            PasswordRecoveryVerifierStore.clear()
            phase = .success(signedIn: signedIn)
        } catch {
            formError = Self.updateMessage(for: error)
            if Self.isExpired(error) {
                recoverySession = nil
            }
        }
    }

    func dismiss() {
        verifyTask?.cancel()
        verifyTask = nil
        recoverySession = nil
        formError = nil
        isSaving = false
        phase = .hidden
    }

    private func resolve(_ link: PasswordRecoveryLink, attempt: UInt64) async {
        let session: AuthenticationSession
        do {
            session = try await establishSession(link)
        } catch is CancellationError {
            return
        } catch {
            guard attempt == self.attempt else { return }
            phase = .invalid(Self.establishMessage(for: error))
            return
        }
        guard attempt == self.attempt, !Task.isCancelled else { return }
        recoverySession = session
        phase = .ready
    }

    private func establishSession(_ link: PasswordRecoveryLink) async throws -> AuthenticationSession {
        switch link {
        case .invalid:
            throw AuthenticationError.sessionExpired
        case .implicit(let accessToken, let refreshToken):
            guard let session = PasswordRecoveryLink.implicitSession(
                accessToken: accessToken,
                refreshToken: refreshToken
            ) else {
                throw AuthenticationError.sessionExpired
            }
            return session
        case .pkceCode(let code):
            guard let verifier = try PasswordRecoveryVerifierStore.load(), !verifier.isEmpty else {
                throw AuthenticationError.sessionExpired
            }
            guard let client else { throw AuthenticationError.notConfigured }
            do {
                let session = try await client.exchangePKCE(code: code, verifier: verifier)
                PasswordRecoveryVerifierStore.clear()
                return session
            } catch {
                if !Self.isNetwork(error) {
                    PasswordRecoveryVerifierStore.clear()
                }
                throw error
            }
        case .tokenHash(let token):
            guard let client else { throw AuthenticationError.notConfigured }
            return try await client.verifyTokenHash(token)
        }
    }

    private static func establishMessage(for error: Error) -> String {
        if isNetwork(error) { return PasswordRecoveryLink.networkMessage }
        return PasswordRecoveryLink.invalidMessage
    }

    private static func updateMessage(for error: Error) -> String {
        if isNetwork(error) { return PasswordRecoveryLink.networkMessage }
        if let auth = error as? AuthenticationError, case .invalidPassword = auth {
            return PasswordRecoveryLink.samePasswordMessage
        }
        if isExpired(error) { return PasswordRecoveryLink.invalidMessage }
        return PasswordRecoveryLink.updateFailedMessage
    }

    private static func isExpired(_ error: Error) -> Bool {
        guard let auth = error as? AuthenticationError else { return false }
        switch auth {
        case .sessionExpired, .sessionMissing, .invalidCredentials, .refreshFailed:
            return true
        default:
            return false
        }
    }

    private static func isNetwork(_ error: Error) -> Bool {
        guard let auth = error as? AuthenticationError else { return false }
        if case .unknown(let message) = auth {
            return message == "networkUnavailable"
                || message == "serverUnavailable"
                || message.hasPrefix("Network connection failed")
        }
        return false
    }
}

nonisolated struct LivePasswordRecoveryClient: PasswordRecoveryClient {
    let backend: SupabaseAuthenticationBackend

    func exchangePKCE(code: String, verifier: String) async throws -> AuthenticationSession {
        try await backend.exchangeOAuthPKCECode(code, codeVerifier: verifier, provider: .email)
    }

    func verifyTokenHash(_ tokenHash: String) async throws -> AuthenticationSession {
        try await backend.verifyRecoveryTokenHash(tokenHash)
    }

    func updatePassword(accessToken: String, newPassword: String) async throws {
        try await backend.updatePassword(accessToken: accessToken, newPassword: newPassword)
    }
}
