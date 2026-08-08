import AuthenticationServices
import CryptoKit
import Foundation
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
        let credential = try await credentialSource.requestCredential()
        return try await backend.signInWithIDToken(
            provider: .apple,
            idToken: credential.idToken,
            nonce: credential.nonce
        )
    }

    func signOut(session: AuthenticationSession) async throws {
        try await backend.signOut(accessToken: session.accessToken)
    }
}

nonisolated struct AppleIDCredentialPayload: Sendable {
    var idToken: String
    var nonce: String?
}

nonisolated protocol AppleCredentialProviding: Sendable {
    func requestCredential() async throws -> AppleIDCredentialPayload
}

/// Uses AuthenticationServices. Presentation anchor resolves the key window when available.
final class SystemAppleCredentialSource: NSObject, AppleCredentialProviding, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, @unchecked Sendable {
    private var continuation: CheckedContinuation<AppleIDCredentialPayload, Error>?
    private var currentNonce: String?

    func requestCredential() async throws -> AppleIDCredentialPayload {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            DispatchQueue.main.async {
                controller.performRequests()
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
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            continuation?.resume(throwing: AuthenticationError.providerUnavailable(.apple))
            continuation = nil
            return
        }
        continuation?.resume(
            returning: AppleIDCredentialPayload(idToken: idToken, nonce: currentNonce)
        )
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthenticationError.cancelled)
        } else {
            continuation?.resume(throwing: AuthenticationError.providerUnavailable(.apple))
        }
        continuation = nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess { continue }
            if Int(random) < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
