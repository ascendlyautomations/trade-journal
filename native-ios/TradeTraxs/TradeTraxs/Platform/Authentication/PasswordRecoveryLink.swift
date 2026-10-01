import Foundation

/// Production Supabase recovery landing URL.
///
/// Matches the web `redirectTo` (`/reset-password`) and `{{ .ConfirmationURL }}`.
/// PKCE recoveries arrive as `?code=`. Implicit recoveries use the URL fragment.
/// Expired links arrive as `error` / `error_code` query items.
nonisolated enum PasswordRecoveryLink: Equatable, Sendable {
    case pkceCode(String)
    case tokenHash(String)
    case implicit(accessToken: String, refreshToken: String?)
    case invalid

    static let productionRedirectURL = "https://www.tradetraxs.com/reset-password"

    static let invalidMessage = "This password reset link is invalid or has expired."
    static let networkMessage = "Check your connection and try again."
    static let updateFailedMessage = "Could not update your password. Please try again."
    static let samePasswordMessage = "Choose a different password than your current one."

    /// Nil when `url` is not a password-reset link.
    static func parse(_ url: URL) -> PasswordRecoveryLink? {
        guard isResetURL(url) else { return nil }
        let values = NativeOAuthConfiguration.fragmentOrQueryItems(from: url)
        if hasProviderError(values) {
            return .invalid
        }
        if let code = trimmed(values["code"]) {
            return .pkceCode(code)
        }
        let type = values["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let recoveryType = type == nil || type == "recovery"
        if recoveryType, let token = trimmed(values["token_hash"] ?? values["token"]) {
            return .tokenHash(token)
        }
        if recoveryType, let accessToken = trimmed(values["access_token"]) {
            return .implicit(
                accessToken: accessToken,
                refreshToken: trimmed(values["refresh_token"])
            )
        }
        return .invalid
    }

    static func validationMessage(password: String, confirmation: String) -> String? {
        if password.isEmpty {
            return "Enter a new password."
        }
        if password.count < 8 {
            return "Password must be at least 8 characters."
        }
        if confirmation.isEmpty {
            return "Confirm your password."
        }
        if password != confirmation {
            return "Passwords do not match."
        }
        return nil
    }

    static func implicitSession(accessToken: String, refreshToken: String?) -> AuthenticationSession? {
        guard let userID = jwtSubject(accessToken) else { return nil }
        return AuthenticationSession(
            userID: UserID(userID),
            email: nil,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
    }

    private static func isResetURL(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "https" || scheme == "http" {
            let host = (url.host ?? "").lowercased()
            guard host == "www.tradetraxs.com" || host == "tradetraxs.com" else { return false }
        } else if scheme != "tradetraxs"
            && scheme != "com.tradetraxs.tradetraxs"
            && scheme != "com.tradetraxs.ios"
        {
            return false
        }
        let parts = url.pathComponentsFiltered.map { $0.lowercased() }
        let head = parts.first
        if head == "reset-password" || head == "forgot-password" || head == "resetpassword" {
            return true
        }
        return head == "auth"
            && (parts.dropFirst().first == "reset-password"
                || parts.dropFirst().first == "forgot-password"
                || parts.dropFirst().first == "resetpassword")
    }

    private static func hasProviderError(_ values: [String: String]) -> Bool {
        trimmed(values["error"]) != nil
            || trimmed(values["error_code"]) != nil
            || trimmed(values["error_description"]) != nil
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func jwtSubject(_ token: String) -> String? {
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
        let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
