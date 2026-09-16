import Foundation
import OSLog

#if DEBUG
nonisolated enum TradovateConnectionDiagnostics {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "TradovateConnection")

    static func requestStarted() {
        log.debug("[TradovateConnection] request.started")
    }

    static func requestSucceeded(
        httpStatus: Int,
        connectionCount: Int,
        activeConnectionCount: Int,
        durationMs: Double
    ) {
        log.debug(
            """
            [TradovateConnection] httpStatus=\(httpStatus, privacy: .public) \
            connectionCount=\(connectionCount, privacy: .public) \
            activeConnectionCount=\(activeConnectionCount, privacy: .public) \
            request.durationMs=\(String(format: "%.1f", durationMs), privacy: .public)
            """
        )
    }

    static func requestFailed(category: String, durationMs: Double) {
        log.error(
            """
            [TradovateConnection] request.failed category=\(category, privacy: .public) \
            request.durationMs=\(String(format: "%.1f", durationMs), privacy: .public)
            """
        )
    }

    static func safeFailureCategory(for error: Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }
        if let app = error as? AppError {
            switch app {
            case .cancelled:
                return "cancelled"
            case .authentication:
                return "auth"
            case .transport(let network):
                return transportCategory(network)
            case .unknown:
                return "decodeOrUnknown"
            case .notImplemented:
                return "notImplemented"
            }
        }
        return "unknown"
    }

    private static func transportCategory(_ error: NetworkError) -> String {
        switch error {
        case .connectivity:
            return "offline"
        case .timeout:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .unauthorized:
            return "auth"
        case .forbidden:
            return "forbidden"
        case .rateLimited:
            return "rateLimited"
        case .server(let statusCode, _):
            return "http\(statusCode)"
        case .decoding:
            return "decode"
        case .validation(let statusCode, _):
            if let statusCode { return "http\(statusCode)" }
            return "httpValidation"
        case .unknown:
            return "transport"
        }
    }
}
#else
nonisolated enum TradovateConnectionDiagnostics {
    static func requestStarted() {}
    static func requestSucceeded(httpStatus: Int, connectionCount: Int, activeConnectionCount: Int, durationMs: Double) {}
    static func requestFailed(category: String, durationMs: Double) {}
    static func safeFailureCategory(for error: Error) -> String { "unknown" }
}
#endif
