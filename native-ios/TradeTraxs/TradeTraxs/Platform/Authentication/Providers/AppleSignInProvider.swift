@preconcurrency import AuthenticationServices
import Foundation
import Synchronization
import UIKit

/// Apple Sign In → Supabase `id_token` exchange.
nonisolated struct AppleSignInProvider: OAuthProviding {
    let kind: AuthenticationProviderKind = .apple
    private let backend: any AuthenticationBackend
    private let credentialSource: any AppleCredentialProviding

    init(
        backend: any AuthenticationBackend,
        credentialSource: any AppleCredentialProviding = SystemAppleCredentialSource()
    ) {
        self.backend = backend
        self.credentialSource = credentialSource
    }

    func signIn() async throws -> AuthenticationSession {
        try await signInWithResult().session
    }

    func signInWithResult() async throws -> AppleSignInResult {
        let credential = try await credentialSource.requestCredential()
        return try await signIn(credential: credential)
    }

    func signIn(credential: AppleIDCredentialPayload) async throws -> AppleSignInResult {
        let session = try await backend.signInWithIDToken(
            provider: .apple,
            idToken: credential.idToken,
            nonce: credential.nonce
        )
        let hint = OAuthFirstLoginHint.normalized(
            fullName: credential.fullName,
            email: credential.email
        )
        return AppleSignInResult(
            session: session,
            firstLoginHint: hint.hasContent ? hint : nil
        )
    }

    func signOut(session: AuthenticationSession) async throws {
        try await backend.signOut(accessToken: session.accessToken)
    }
}

nonisolated struct AppleSignInResult: Sendable {
    var session: AuthenticationSession
    var firstLoginHint: OAuthFirstLoginHint?
}

nonisolated struct AppleIDCredentialPayload: Sendable, Equatable {
    var idToken: String
    var nonce: String?
    /// Only present on the user's first Apple authorization for this app.
    var fullName: String?
    /// Only present on the user's first Apple authorization when Apple shares it.
    var email: String?
}

nonisolated protocol AppleCredentialProviding: Sendable {
    func requestCredential() async throws -> AppleIDCredentialPayload
}

/// Test double — inject Apple credentials without AuthenticationServices UI.
nonisolated struct StaticAppleCredentialSource: AppleCredentialProviding {
    let payload: AppleIDCredentialPayload

    func requestCredential() async throws -> AppleIDCredentialPayload {
        payload
    }
}

/// Uses AuthenticationServices. Presentation anchor resolves the key window when available.
nonisolated final class SystemAppleCredentialSource: NSObject, AppleCredentialProviding, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, @unchecked Sendable {
    private struct CredentialState {
        var continuation: CheckedContinuation<AppleIDCredentialPayload, Error>?
        var currentNonce: String?
    }

    private let state = Mutex(CredentialState())
    private nonisolated(unsafe) var retainedAuthorizationController: ASAuthorizationController?

    func requestCredential() async throws -> AppleIDCredentialPayload {
        let nonce = AppleSignInNonce.generate()
        state.withLock { credentialState in
            credentialState.currentNonce = nonce
        }
        return try await withCheckedThrowingContinuation { continuation in
            state.withLock { credentialState in
                credentialState.continuation = continuation
            }
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256Hex(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            retainedAuthorizationController = controller
            Task { @MainActor [weak self] in
                self?.retainedAuthorizationController?.performRequests()
            }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        if let window = scenes.flatMap(\.windows).first {
            return window
        }
        return UIWindow()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let resumeState = state.withLock { credentialState -> (CheckedContinuation<AppleIDCredentialPayload, Error>?, String?) in
            let resume = credentialState.continuation
            let nonce = credentialState.currentNonce
            credentialState.continuation = nil
            return (resume, nonce)
        }
        retainedAuthorizationController = nil

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            resumeState.0?.resume(throwing: AuthenticationError.providerTokenInvalid(.apple))
            return
        }
        resumeState.0?.resume(
            returning: AppleIDCredentialPayload(
                idToken: idToken,
                nonce: resumeState.1,
                fullName: credential.fullName?.formattedDisplayName(),
                email: ProfileDisplayNamePolicy.normalized(credential.email)
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let resume = state.withLock { credentialState -> CheckedContinuation<AppleIDCredentialPayload, Error>? in
            let resume = credentialState.continuation
            credentialState.continuation = nil
            return resume
        }
        retainedAuthorizationController = nil

        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            resume?.resume(throwing: AuthenticationError.cancelled)
        } else {
            resume?.resume(throwing: AuthenticationError.providerUnavailable(.apple))
        }
    }
}
