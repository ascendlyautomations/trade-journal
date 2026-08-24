import Foundation
import OSLog

/// DEBUG-only structured auth/session tracing. Never logs credentials or user identifiers.
enum AuthFlowPhase: String, Sendable {
    case unknown
    case restoring
    case unauthenticated
    case authenticating
    case authenticated
    case bootstrapLoading
    case bootstrapFailed
}

#if DEBUG
enum AuthFlowTracer {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "AuthFlow"
    )
    private static let lock = NSLock()
    private static var correlationCounter: UInt64 = 0
    private static var marks: [String: CFAbsoluteTime] = [:]

    static func beginCorrelation() -> String {
        lock.lock()
        correlationCounter &+= 1
        let id = "auth-\(correlationCounter)"
        lock.unlock()
        return id
    }

    static func trace(
        _ event: String,
        phase: AuthFlowPhase,
        correlation: String? = nil,
        onMainActor: Bool = Thread.isMainThread
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let started = marks[event]
        marks[event] = now
        lock.unlock()
        let durationMs: String
        if let started {
            durationMs = String(format: "%.1f", (now - started) * 1_000)
        } else {
            durationMs = "—"
        }
        logger.debug(
            "[\(correlation ?? "—", privacy: .public)] \(event, privacy: .public) phase=\(phase.rawValue, privacy: .public) main=\(onMainActor, privacy: .public) dtMs=\(durationMs, privacy: .public)"
        )
    }
}
#else
enum AuthFlowTracer {
    static func beginCorrelation() -> String { "" }
    static func trace(
        _ event: String,
        phase: AuthFlowPhase,
        correlation: String? = nil,
        onMainActor: Bool = true
    ) {}
}
#endif

extension AuthenticationState {
    var authFlowPhase: AuthFlowPhase {
        switch self {
        case .unknown:
            return .unknown
        case .unauthenticated, .failure:
            return .unauthenticated
        case .authenticating:
            return .authenticating
        case .authenticated, .refreshing, .locked:
            return .authenticated
        }
    }
}
