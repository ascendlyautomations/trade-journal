import Foundation
import OSLog

/// Logs outbound requests without headers/bodies (PII-safe).
nonisolated struct LoggingRequestInterceptor: RequestInterceptor {
    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        AppLog.networking.info(
            "→ \(request.method.rawValue, privacy: .public) \(request.url.host ?? "", privacy: .public)\(request.url.path, privacy: .public)"
        )
        return request
    }
}
