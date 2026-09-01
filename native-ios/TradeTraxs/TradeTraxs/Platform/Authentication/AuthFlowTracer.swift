import Foundation
import OSLog

/// DEBUG-only structured auth/session tracing. Never logs credentials or user identifiers.
nonisolated enum AuthFlowPhase: String, Sendable {
    case unknown
    case restoring
    case unauthenticated
    case authenticating
    case authenticated
    case bootstrapLoading
    case bootstrapFailed
}

nonisolated enum AuthRefreshTraceResult: String, Sendable {
    case success
    case terminalFailure
    case transientFailure
}

#if DEBUG
nonisolated enum AuthFlowTracer {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "AuthFlow"
    )
    private static let lock = NSLock()
    nonisolated(unsafe) private static var correlationCounter: UInt64 = 0
    nonisolated(unsafe) private static var marks: [String: CFAbsoluteTime] = [:]
    nonisolated(unsafe) private static var lastRootPhase: AuthFlowPhase = .unknown

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
        generation: UInt64? = nil,
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
        let generationLabel = generation.map { "generation=\($0)" } ?? ""
        logger.debug(
            "[\(correlation ?? "—", privacy: .public)] \(event, privacy: .public) phase=\(phase.rawValue, privacy: .public) \(generationLabel, privacy: .public) main=\(onMainActor, privacy: .public) dtMs=\(durationMs, privacy: .public)"
        )
    }

    static func traceRefreshCompleted(_ result: AuthRefreshTraceResult, generation: UInt64) {
        trace(
            "auth.refresh.completed result=\(result.rawValue)",
            phase: result == .success ? .authenticated : .restoring,
            generation: generation
        )
    }

    static func traceRootTransition(to phase: AuthFlowPhase, generation: UInt64) {
        lock.lock()
        let from = lastRootPhase
        lastRootPhase = phase
        lock.unlock()
        trace(
            "auth.root.transition from=\(from.rawValue) to=\(phase.rawValue)",
            phase: phase,
            generation: generation
        )
    }

    static func traceBootstrapAllowed(_ allowed: Bool, generation: UInt64) {
        trace(
            "auth.bootstrap.allowed=\(allowed)",
            phase: allowed ? .authenticated : .restoring,
            generation: generation
        )
    }
}
#else
nonisolated enum AuthFlowTracer {
    static func beginCorrelation() -> String { "" }
    static func trace(
        _ event: String,
        phase: AuthFlowPhase,
        correlation: String? = nil,
        generation: UInt64? = nil,
        onMainActor: Bool = true
    ) {}
    static func traceRefreshCompleted(_ result: AuthRefreshTraceResult, generation: UInt64) {}
    static func traceRootTransition(to phase: AuthFlowPhase, generation: UInt64) {}
    static func traceBootstrapAllowed(_ allowed: Bool, generation: UInt64) {}
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
        case .refreshing, .sessionValidationFailed:
            return .restoring
        case .authenticated, .locked:
            return .authenticated
        }
    }
}
