import AuthenticationServices
import Foundation
import UIKit

/// Presents Supabase OAuth (Google) via ``ASWebAuthenticationSession``.
nonisolated final class SupabaseOAuthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let callbackScheme = "tradetraxs"

    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func signIn(provider: String) async throws -> AuthenticationSession {
        guard configuration.isSupabaseConfigured,
              let base = configuration.supabaseURL,
              let anonKey = configuration.supabaseAnonKey
        else {
            throw AuthenticationError.notConfigured
        }

        var baseString = base.absoluteString
        if baseString.hasSuffix("/") { baseString.removeLast() }
        var components = URLComponents(string: baseString + "/auth/v1/authorize")
        let redirect = "\(Self.callbackScheme)://auth-callback"
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirect),
            URLQueryItem(name: "apikey", value: anonKey),
        ]
        guard let url = components?.url else {
            throw AuthenticationError.providerUnavailable(.google)
        }

        let callbackURL = try await startSession(url: url)
        return try Self.session(from: callbackURL, provider: .google)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        return scenes.flatMap(\.windows).first ?? UIWindow()
    }

    private func startSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    {
                        continuation.resume(throwing: AuthenticationError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthenticationError.providerUnavailable(.google))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthenticationError.providerUnavailable(.google))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            DispatchQueue.main.async {
                if !session.start() {
                    continuation.resume(throwing: AuthenticationError.providerUnavailable(.google))
                }
            }
        }
    }

    private static func session(from url: URL, provider: AuthenticationProviderKind) throws -> AuthenticationSession {
        let values = fragmentOrQueryItems(from: url)
        guard let accessToken = values["access_token"], !accessToken.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
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

    private static func fragmentOrQueryItems(from url: URL) -> [String: String] {
        var values: [String: String] = [:]
        if let fragment = url.fragment {
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    values[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                }
            }
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                if let value = item.value {
                    values[item.name] = value
                }
            }
        }
        return values
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

    init(configuration: AppConfiguration) {
        self.browser = SupabaseOAuthBrowser(configuration: configuration)
    }

    func signIn() async throws -> AuthenticationSession {
        try await browser.signIn(provider: "google")
    }
}
