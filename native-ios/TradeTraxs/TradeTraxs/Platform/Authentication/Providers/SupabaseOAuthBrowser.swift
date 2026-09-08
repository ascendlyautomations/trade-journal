@preconcurrency import AuthenticationServices
import Foundation
import OSLog
import UIKit

/// Presents Supabase OAuth (Google) via ``ASWebAuthenticationSession``.
nonisolated final class SupabaseOAuthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let configuration: AppConfiguration
    private let backend: SupabaseAuthenticationBackend

    init(configuration: AppConfiguration, backend: SupabaseAuthenticationBackend) {
        self.configuration = configuration
        self.backend = backend
    }

    func signIn(provider: String) async throws -> AuthenticationSession {
        guard configuration.isSupabaseConfigured,
              let base = configuration.supabaseURL,
              let anonKey = configuration.supabaseAnonKey
        else {
            throw AuthenticationError.notConfigured
        }

        let redirect = NativeOAuthConfiguration.httpsBridgeURL(configuration: configuration)
        let codeVerifier = NativeOAuthConfiguration.generateCodeVerifier()
        let codeChallenge = NativeOAuthConfiguration.codeChallenge(for: codeVerifier)

        var baseString = base.absoluteString
        if baseString.hasSuffix("/") { baseString.removeLast() }
        var components = URLComponents(string: baseString + "/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirect.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "apikey", value: anonKey),
        ]
        guard let url = components?.url else {
            throw AuthenticationError.providerUnavailable(.google)
        }

        AppLog.authentication.info(
            "OAuth: started provider=\(provider, privacy: .public) redirect_to=\(redirect.absoluteString, privacy: .public)"
        )

        let callbackURL = try await startSession(url: url)
        AppLog.authentication.info(
            "OAuth: callback received scheme=\(callbackURL.scheme ?? "nil", privacy: .public)"
        )

        let session = try await session(from: callbackURL, codeVerifier: codeVerifier, provider: .google)
        AppLog.authentication.info("OAuth PKCE exchange succeeded")
        return session
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        return scenes.flatMap(\.windows).first ?? UIWindow()
    }

    private func startSession(url: URL) async throws -> URL {
        let bridge = OAuthWebAuthenticationSessionBridge()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                bridge.bind(continuation: continuation)

                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: NativeOAuthConfiguration.callbackScheme
                ) { callbackURL, error in
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                        {
                            _ = bridge.finishOnce(
                                with: .failure(AuthenticationError.cancelled),
                                source: .userCancellation
                            )
                        } else {
                            AppLog.authentication.error(
                                "OAuth: ASWebAuthenticationSession failed — \(error.localizedDescription, privacy: .public)"
                            )
                            _ = bridge.finishOnce(
                                with: .failure(AuthenticationError.providerUnavailable(.google)),
                                source: .sessionError
                            )
                        }
                        return
                    }
                    guard let callbackURL else {
                        AppLog.authentication.error("OAuth: callback URL missing")
                        _ = bridge.finishOnce(
                            with: .failure(AuthenticationError.providerUnavailable(.google)),
                            source: .missingCallbackURL
                        )
                        return
                    }
                    guard NativeOAuthConfiguration.isOAuthCallbackURL(callbackURL) else {
                        AppLog.authentication.error(
                            "OAuth: unexpected callback host=\(callbackURL.host ?? "nil", privacy: .public) path=\(callbackURL.path, privacy: .public)"
                        )
                        _ = bridge.finishOnce(
                            with: .failure(AuthenticationError.providerUnavailable(.google)),
                            source: .invalidCallbackURL
                        )
                        return
                    }
                    _ = bridge.finishOnce(with: .success(callbackURL), source: .callbackSuccess)
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                bridge.attach(session: session)

                DispatchQueue.main.async {
                    AppLog.authentication.info("OAuth: session started")
                    if !session.start() {
                        _ = bridge.finishOnce(
                            with: .failure(AuthenticationError.providerUnavailable(.google)),
                            source: .startFailed
                        )
                    }
                }
            }
        } onCancel: {
            _ = bridge.finishOnce(
                with: .failure(AuthenticationError.cancelled),
                source: .taskCancellation
            )
            bridge.cancelSession()
        }
    }

    private func session(
        from url: URL,
        codeVerifier: String,
        provider: AuthenticationProviderKind
    ) async throws -> AuthenticationSession {
        let values = NativeOAuthConfiguration.fragmentOrQueryItems(from: url)

        if let errorDescription = values["error_description"] ?? values["error"] {
            AppLog.authentication.error(
                "OAuth: provider error — \(errorDescription, privacy: .public)"
            )
            throw AuthenticationError.providerUnavailable(provider)
        }

        if let authCode = values["code"], !authCode.isEmpty {
            AppLog.authentication.info("OAuth PKCE exchange started")
            return try await backend.exchangeOAuthPKCECode(
                authCode,
                codeVerifier: codeVerifier,
                provider: provider
            )
        }

        if let accessToken = values["access_token"], !accessToken.isEmpty {
            AppLog.authentication.info("OAuth: using implicit callback tokens")
            return try Self.sessionFromImplicitTokens(values, provider: provider, accessToken: accessToken)
        }

        AppLog.authentication.error("OAuth: callback missing code and access_token")
        throw AuthenticationError.invalidCredentials
    }

    private static func sessionFromImplicitTokens(
        _ values: [String: String],
        provider: AuthenticationProviderKind,
        accessToken: String
    ) throws -> AuthenticationSession {
        let refreshToken = values["refresh_token"]
        let expiresIn = Double(values["expires_in"] ?? "") ?? 3600
        let userID = values["user_id"]
            ?? decodeJWTSubject(accessToken)
            ?? UUID().uuidString

        return AuthenticationSession(
            userID: UserID(userID),
            email: values["email"],
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            provider: provider,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
    }

    private static func decodeJWTSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else {
            return nil
        }
        return sub
    }
}

/// Google sign-in via Supabase hosted OAuth (no Google SDK).
nonisolated struct SupabaseGoogleOAuthPerformer: GoogleSignInPerforming {
    private let browser: SupabaseOAuthBrowser

    init(configuration: AppConfiguration, backend: SupabaseAuthenticationBackend) {
        self.browser = SupabaseOAuthBrowser(configuration: configuration, backend: backend)
    }

    func signIn() async throws -> AuthenticationSession {
        try await browser.signIn(provider: "google")
    }
}
