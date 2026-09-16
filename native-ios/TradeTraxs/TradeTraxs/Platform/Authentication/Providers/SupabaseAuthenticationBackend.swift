import Foundation
import OSLog

/// Production GoTrue backend. Implements ``AuthenticationBackend`` over Networking.
nonisolated struct SupabaseAuthenticationBackend: AuthenticationBackend {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func signIn(email: String, password: String) async throws -> AuthenticationSession {
        struct Body: Encodable {
            var email: String
            var password: String
        }
        return try await tokenRequest(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: Body(email: email, password: password),
            provider: .email,
            requiresAuthentication: false
        )
    }

    func signUp(email: String, password: String) async throws -> AuthenticationSession {
        struct Body: Encodable {
            var email: String
            var password: String
        }
        guard transport.isConfigured else { throw AuthenticationError.notConfigured }
        do {
            let response = try await transport.send(
                host: .supabase,
                path: "/auth/v1/signup",
                method: .post,
                body: try transport.encodeJSON(Body(email: email, password: password)),
                requiresAuthentication: false
            )
            return try parseSignupResponse(
                response: response,
                fallbackEmail: email,
                provider: .email
            )
        } catch let error as AppError {
            throw mapSignupRequestError(error)
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.unknown(error.localizedDescription)
        }
    }

    func signOut(accessToken: String) async throws {
        _ = try await transport.send(
            host: .supabase,
            path: "/auth/v1/logout",
            method: .post,
            headers: ["Authorization": "Bearer \(accessToken)"],
            requiresAuthentication: false
        )
    }

    func refresh(refreshToken: String) async throws -> AuthenticationSession {
        struct Body: Encodable {
            var refresh_token: String
        }
        do {
            return try await tokenRequest(
                path: "/auth/v1/token",
                query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                body: Body(refresh_token: refreshToken),
                provider: .email,
                requiresAuthentication: false
            )
        } catch let error as AuthenticationError {
            if error.isTerminalRefreshFailure || error == .invalidCredentials {
                throw AuthenticationError.refreshFailed
            }
            throw error
        } catch let error as AppError {
            throw AuthenticationError.fromRefreshFailure(error)
        } catch {
            throw AuthenticationError.fromRefreshFailure(error)
        }
    }

    func requestPasswordReset(email: String) async throws {
        struct Body: Encodable {
            var email: String
        }
        _ = try await transport.send(
            host: .supabase,
            path: "/auth/v1/recover",
            method: .post,
            body: try transport.encodeJSON(Body(email: email)),
            requiresAuthentication: false
        )
    }

    func resendSignupConfirmation(email: String) async throws {
        struct Body: Encodable {
            var type: String
            var email: String
        }
        guard transport.isConfigured else { throw AuthenticationError.notConfigured }
        _ = try await transport.send(
            host: .supabase,
            path: "/auth/v1/resend",
            method: .post,
            body: try transport.encodeJSON(Body(type: "signup", email: email)),
            requiresAuthentication: false
        )
    }

    func updateUserMetadata(accessToken: String, metadata: [String: String]) async throws {
        struct Body: Encodable {
            var data: [String: String]
        }
        guard transport.isConfigured else { throw AuthenticationError.notConfigured }
        _ = try await transport.send(
            host: .supabase,
            path: "/auth/v1/user",
            method: .put,
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: try transport.encodeJSON(Body(data: metadata)),
            requiresAuthentication: false
        )
    }

    func signInWithIDToken(
        provider: AuthenticationProviderKind,
        idToken: String,
        nonce: String?
    ) async throws -> AuthenticationSession {
        struct Body: Encodable {
            var provider: String
            var id_token: String
            var nonce: String?
        }
        let providerName: String
        switch provider {
        case .apple: providerName = "apple"
        case .google: providerName = "google"
        default: throw AuthenticationError.providerUnavailable(provider)
        }
        return try await tokenRequest(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: Body(provider: providerName, id_token: idToken, nonce: nonce),
            provider: provider,
            requiresAuthentication: false
        )
    }

    /// PKCE code exchange after Google OAuth returns to the native callback deep link.
    func exchangeOAuthPKCECode(
        _ authCode: String,
        codeVerifier: String,
        provider: AuthenticationProviderKind = .google
    ) async throws -> AuthenticationSession {
        struct Body: Encodable {
            var auth_code: String
            var code_verifier: String
        }
        return try await tokenRequest(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "pkce")],
            body: Body(auth_code: authCode, code_verifier: codeVerifier),
            provider: provider,
            requiresAuthentication: false
        )
    }

    // MARK: - Private

    private func tokenRequest<Body: Encodable>(
        path: String,
        query: [URLQueryItem],
        body: Body,
        provider: AuthenticationProviderKind,
        requiresAuthentication: Bool
    ) async throws -> AuthenticationSession {
        guard transport.isConfigured else {
#if DEBUG
            if provider == .apple {
                AppLog.authentication.debug("[AppleAuth] supabase.tokenRequest.skipped reason=notConfigured")
            }
#endif
            throw AuthenticationError.notConfigured
        }
        do {
#if DEBUG
            if provider == .apple {
                AppLog.authentication.debug("[AppleAuth] supabase.tokenRequest.started grant=id_token")
            }
#endif
            let response = try await transport.send(
                host: .supabase,
                path: path,
                method: .post,
                queryItems: query,
                body: try transport.encodeJSON(body),
                requiresAuthentication: requiresAuthentication
            )
            let payload = try transport.decoder.decode(GoTrueTokenResponse.self, from: response)
            return try payload.makeSession(provider: provider)
        } catch let error as AppError {
            throw mapTokenRequestError(error, provider: provider)
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.unknown(error.localizedDescription)
        }
    }

    private func mapTokenRequestError(
        _ error: AppError,
        provider: AuthenticationProviderKind
    ) -> AuthenticationError {
        if case .transport(let network) = error {
            switch network {
            case .connectivity, .timeout:
                return .unknown("Network connection failed. Check your connection and try again.")
            case .cancelled:
                return .cancelled
            case .server(let code, let message):
                if provider != .email, (502...504).contains(code) {
                    return .unknown("serverUnavailable")
                }
                return mapProviderServerFailure(
                    statusCode: code,
                    message: message,
                    provider: provider
                )
            case .unauthorized:
                if provider == .email {
                    return .invalidCredentials
                }
                return .providerTokenInvalid(provider)
            case .forbidden, .rateLimited, .decoding, .validation, .unknown:
                break
            }
        }
        if case .authentication(let auth) = error {
            return auth
        }
        return .unknown(String(describing: error))
    }

    private func parseSignupResponse(
        response: HTTPResponse,
        fallbackEmail: String,
        provider: AuthenticationProviderKind
    ) throws -> AuthenticationSession {
        let envelope = try transport.decoder.decode(GoTrueSignupEnvelope.self, from: response)
        if let session = try envelope.makeSessionIfPresent(provider: provider) {
            return session
        }
        let resolvedEmail = envelope.normalizedUser()?.email ?? fallbackEmail
        if envelope.normalizedUser()?.id?.isEmpty == false {
            throw AuthenticationError.emailConfirmationRequired(email: resolvedEmail)
        }
        throw AuthenticationError.sessionMissing
    }

    private func mapSignupRequestError(_ error: AppError) -> AuthenticationError {
        if GoTrueAuthErrorParsing.isEmailAlreadyRegistered(error) {
            return .emailAlreadyRegistered
        }
        return mapTokenRequestError(error, provider: .email)
    }

    private func mapProviderServerFailure(
        statusCode: Int,
        message: String?,
        provider: AuthenticationProviderKind
    ) -> AuthenticationError {
        let body = message?.lowercased() ?? ""
        if provider == .email {
            if GoTrueAuthErrorParsing.isEmailAlreadyRegisteredMessage(body) {
                return .emailAlreadyRegistered
            }
            if statusCode == 400 || statusCode == 401 {
                return .invalidCredentials
            }
        } else {
            if body.contains("provider") && (body.contains("not enabled") || body.contains("disabled")) {
                return .providerMisconfigured(provider)
            }
            if statusCode == 400 || statusCode == 401 || statusCode == 422 {
                return .providerTokenInvalid(provider)
            }
        }
        if statusCode == 400 || statusCode == 401 {
            return provider == .email ? .invalidCredentials : .providerTokenInvalid(provider)
        }
        return .unknown(message ?? "Authentication failed.")
    }
}

private nonisolated struct GoTrueSignupEnvelope: Decodable {
    var access_token: String?
    var refresh_token: String?
    var expires_in: Double?
    var token_type: String?
    var user: GoTrueUser?
    var id: String?
    var email: String?

    func normalizedUser() -> GoTrueUser? {
        if let user { return user }
        guard let id, !id.isEmpty else { return nil }
        return GoTrueUser(id: id, email: email)
    }

    func makeSessionIfPresent(provider: AuthenticationProviderKind) throws -> AuthenticationSession? {
        guard let userID = normalizedUser()?.id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty
        else {
            return nil
        }
        guard let accessToken = access_token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty
        else {
            return nil
        }
        let expires = Date().addingTimeInterval(expires_in ?? 3600)
        return AuthenticationSession(
            userID: UserID(userID),
            email: normalizedUser()?.email,
            accessToken: accessToken,
            refreshToken: refresh_token,
            expiresAt: expires,
            provider: provider,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
    }
}

private nonisolated struct GoTrueTokenResponse: Decodable {
    var access_token: String?
    var refresh_token: String?
    var expires_in: Double?
    var token_type: String?
    var user: GoTrueUser?

    func makeSession(provider: AuthenticationProviderKind) throws -> AuthenticationSession {
        let envelope = GoTrueSignupEnvelope(
            access_token: access_token,
            refresh_token: refresh_token,
            expires_in: expires_in,
            token_type: token_type,
            user: user,
            id: nil,
            email: nil
        )
        guard let session = try envelope.makeSessionIfPresent(provider: provider) else {
            throw AuthenticationError.sessionMissing
        }
        return session
    }
}

private nonisolated struct GoTrueUserMetadata: Decodable {
    var full_name: String?
    var name: String?
    var given_name: String?
    var family_name: String?
}

private nonisolated struct GoTrueUser: Decodable {
    var id: String?
    var email: String?
    var user_metadata: GoTrueUserMetadata?
}

/// Parses GoTrue JSON/text errors without exposing a public email lookup.
private nonisolated enum GoTrueAuthErrorParsing {
    static func isEmailAlreadyRegistered(_ error: AppError) -> Bool {
        guard case .transport(let network) = error else { return false }
        switch network {
        case .validation(_, let message):
            return isEmailAlreadyRegisteredMessage(message.lowercased())
        case .server(_, let message):
            return isEmailAlreadyRegisteredMessage(message?.lowercased() ?? "")
        default:
            return false
        }
    }

    static func isEmailAlreadyRegisteredMessage(_ loweredBody: String) -> Bool {
        guard !loweredBody.isEmpty else { return false }
        if loweredBody.contains("user_already_exists") { return true }
        if loweredBody.contains("email address is already registered") { return true }
        if loweredBody.contains("already registered") { return true }
        if loweredBody.contains("identity already exists") { return true }
        if let parsed = parseJSON(loweredBody) {
            if parsed.error_code?.lowercased() == "user_already_exists" { return true }
            let combined = [parsed.msg, parsed.message, parsed.error]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            if combined.contains("already registered") { return true }
        }
        return false
    }

    private static func parseJSON(_ text: String) -> GoTrueErrorWire? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GoTrueErrorWire.self, from: data)
    }

    private struct GoTrueErrorWire: Decodable {
        var error: String?
        var error_code: String?
        var msg: String?
        var message: String?
    }
}
