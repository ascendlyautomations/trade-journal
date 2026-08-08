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
        return try await tokenRequest(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: Body(refresh_token: refreshToken),
            provider: .email,
            requiresAuthentication: false
        )
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
            if case .transport(let network) = error {
                if case .server(let code, _) = network {
                    // Best-effort body is not on NetworkError — map by status.
                    if code == 400 || code == 401 {
                        throw AuthenticationError.invalidCredentials
                    }
                }
            }
            if case .authentication(let auth) = error {
                throw auth
            }
            throw AuthenticationError.unknown(String(describing: error))
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.unknown(error.localizedDescription)
        }
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
        throw AuthenticationError.providerUnavailable(provider)
    }
}
