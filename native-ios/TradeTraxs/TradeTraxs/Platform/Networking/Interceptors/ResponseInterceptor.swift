import Foundation
import OSLog

/// Observes / transforms successful HTTP responses.
nonisolated protocol ResponseInterceptor: Sendable {
    func intercept(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse
}

nonisolated struct CompositeResponseInterceptor: ResponseInterceptor {
    let interceptors: [any ResponseInterceptor]

    func intercept(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse {
        var current = response
        for interceptor in interceptors {
            current = try await interceptor.intercept(current, for: request)
        }
        return current
    }
}

nonisolated struct PassthroughResponseInterceptor: ResponseInterceptor {
    func intercept(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse {
        _ = request
        return response
    }
}

/// Logs response status via AppLog — never logs bodies/tokens.
nonisolated struct LoggingResponseInterceptor: ResponseInterceptor {
    func intercept(_ response: HTTPResponse, for request: HTTPRequest) async throws -> HTTPResponse {
        AppLog.networking.info(
            "← \(request.method.rawValue, privacy: .public) \(request.url.path, privacy: .public) \(response.statusCode, privacy: .public)"
        )
        return response
    }
}
