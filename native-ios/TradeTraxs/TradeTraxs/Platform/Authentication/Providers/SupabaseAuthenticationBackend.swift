import Foundation

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
        return try await tokenRequest(
            path: "/auth/v1/signup",
            query: [],
            body: Body(email: email, password: password),
            provider: .email,
            requiresAuthentication: false
        )
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

    // MARK: - Private

    private func tokenRequest<Body: Encodable>(
        path: String,
        query: [URLQueryItem],
        body: Body,
        provider: AuthenticationProviderKind,
        requiresAuthentication: Bool
    ) async throws -> AuthenticationSession {
        guard transport.isConfigured else { throw AuthenticationError.notConfigured }
        do {
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

    private func mapProviderServerFailure(
        statusCode: Int,
        message: String?,
        provider: AuthenticationProviderKind
    ) -> AuthenticationError {
        let body = message?.lowercased() ?? ""
        if provider == .email {
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

private nonisolated struct GoTrueTokenResponse: Decodable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Double?
    var token_type: String?
    var user: GoTrueUser?

    func makeSession(provider: AuthenticationProviderKind) throws -> AuthenticationSession {
        guard let userID = user?.id, !userID.isEmpty else {
            throw AuthenticationError.sessionMissing
        }
        let expires = Date().addingTimeInterval(expires_in ?? 3600)
        return AuthenticationSession(
            userID: UserID(userID),
            email: user?.email,
            accessToken: access_token,
            refreshToken: refresh_token,
            expiresAt: expires,
            provider: provider,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
    }
}

private nonisolated struct GoTrueUser: Decodable {
    var id: String?
    var email: String?
}

extension AuthenticationBackend {
    func signInWithIDToken(
        provider: AuthenticationProviderKind,
        idToken: String,
        nonce: String?
    ) async throws -> AuthenticationSession {
        if let supabase = self as? SupabaseAuthenticationBackend {
            return try await supabase.signInWithIDToken(
                provider: provider,
                idToken: idToken,
                nonce: nonce
            )
        }
        if let memory = self as? InMemoryAuthenticationBackend {
            return try await memory.signInWithIDToken(
                provider: provider,
                idToken: idToken,
                nonce: nonce
            )
        }
        throw AuthenticationError.providerUnavailable(provider)
    }
}
