import Foundation

/// Typed networking failures. Features map these to ``UserFacingError`` / feedback.
nonisolated enum NetworkError: Error, Sendable, Equatable {
    case connectivity
    case timeout
    case cancelled
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int, message: String?)
    case decoding(message: String)
    case validation(statusCode: Int?, message: String)
    case unknown(message: String)

    var isRetryable: Bool {
        switch self {
        case .connectivity, .timeout, .rateLimited, .server:
            return true
        case .cancelled, .unauthorized, .forbidden, .decoding, .validation, .unknown:
            return false
        }
    }
}

extension AppError {
    static func network(_ error: NetworkError) -> AppError {
        switch error {
        case .cancelled:
            return .cancelled
        default:
            return .transport(error)
        }
    }
}
