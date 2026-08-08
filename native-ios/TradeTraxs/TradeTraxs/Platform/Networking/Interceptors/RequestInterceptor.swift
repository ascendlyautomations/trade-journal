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
        guard request.endpoint.requiresAuthentication else { return request }
        guard let token = await accessTokenProvider(), !token.isEmpty else {
            return request
        }
        var copy = request
        copy.headers["Authorization"] = "Bearer \(token)"
        return copy
    }
}
