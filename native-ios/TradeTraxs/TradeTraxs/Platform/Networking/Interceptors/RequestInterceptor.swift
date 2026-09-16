import Foundation

/// Mutates outbound requests (auth headers, tracing, etc.).
nonisolated protocol RequestInterceptor: Sendable {
    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest
}

/// Composes multiple request interceptors in order.
nonisolated struct CompositeRequestInterceptor: RequestInterceptor {
    let interceptors: [any RequestInterceptor]

    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        var current = request
        for interceptor in interceptors {
            current = try await interceptor.intercept(current)
        }
        return current
    }
}

/// Adds default headers already present on the request builder — reserved for future auth.
nonisolated struct PassthroughRequestInterceptor: RequestInterceptor {
    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        request
    }
}

/// Injects Bearer tokens from the active ``SessionManager`` / Keychain session.
nonisolated struct AuthenticationRequestInterceptor: RequestInterceptor {
    var accessTokenProvider: @Sendable () async -> String? = { nil }

    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        guard request.endpoint.requiresAuthentication else {
            // GoTrue token grants must not await ``SessionNetworkGate`` — the active refresh holds that gate.
            return request
        }

        let userToken = await accessTokenProvider()
        let hasUserToken = userToken.map { !$0.isEmpty } ?? false

        if hasUserToken, let userToken {
            var copy = request
            copy.headers["Authorization"] = "Bearer \(userToken)"
            return copy
        }

        // Do not send an unauthenticated BFF/Supabase call and then surface a cryptic 401.
        throw AppError.authentication(.sessionMissing)
    }
}
