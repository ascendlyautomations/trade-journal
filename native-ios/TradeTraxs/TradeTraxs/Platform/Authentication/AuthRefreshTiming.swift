import Foundation
import OSLog

#if DEBUG
/// DEBUG-only token refresh transport timeline — never logs credentials.
nonisolated enum AuthRefreshTiming {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "AuthRefreshTiming"
    )

    static func operationStarted(path: String, generation: UInt64?) {
        logger.debug(
            "[AuthRefreshTiming] operation.started path=\(path, privacy: .public) \(generationLabel(generation), privacy: .public)"
        )
    }

    static func concurrencyAcquireRequested(path: String, priority: NetworkSchedulingPriority) {
        logger.debug(
            "[AuthRefreshTiming] concurrency.acquire.requested path=\(path, privacy: .public) priority=\(priorityLabel(priority), privacy: .public)"
        )
    }

    static func concurrencyAcquired(path: String, priority: NetworkSchedulingPriority) {
        logger.debug(
            "[AuthRefreshTiming] concurrency.acquired path=\(path, privacy: .public) priority=\(priorityLabel(priority), privacy: .public)"
        )
    }

    static func urlTaskCreated(path: String) {
        logger.debug("[AuthRefreshTiming] urlTask.created path=\(path, privacy: .public)")
    }

    static func urlTaskResumed(path: String) {
        logger.debug("[AuthRefreshTiming] urlTask.resumed path=\(path, privacy: .public)")
    }

    static func responseReceived(path: String, statusCode: Int) {
        logger.debug(
            "[AuthRefreshTiming] response.received path=\(path, privacy: .public) status=\(statusCode, privacy: .public)"
        )
    }

    static func sessionPersisted(generation: UInt64?) {
        logger.debug(
            "[AuthRefreshTiming] session.persisted \(generationLabel(generation), privacy: .public)"
        )
    }

    static func operationCompleted(path: String, outcome: String, durationMs: Int) {
        logger.debug(
            "[AuthRefreshTiming] operation.completed path=\(path, privacy: .public) outcome=\(outcome, privacy: .public) durationMs=\(durationMs, privacy: .public)"
        )
    }

    private static func generationLabel(_ generation: UInt64?) -> String {
        guard let generation else { return "generation=—" }
        return "generation=\(generation)"
    }

    private static func priorityLabel(_ priority: NetworkSchedulingPriority) -> String {
        switch priority {
        case .criticalAuth: return "criticalAuth"
        case .visible: return "visible"
        case .background: return "background"
        }
    }
}
#else
nonisolated enum AuthRefreshTiming {
    static func operationStarted(path: String, generation: UInt64?) {}
    static func concurrencyAcquireRequested(path: String, priority: NetworkSchedulingPriority) {}
    static func concurrencyAcquired(path: String, priority: NetworkSchedulingPriority) {}
    static func urlTaskCreated(path: String) {}
    static func urlTaskResumed(path: String) {}
    static func responseReceived(path: String, statusCode: Int) {}
    static func sessionPersisted(generation: UInt64?) {}
    static func operationCompleted(path: String, outcome: String, durationMs: Int) {}
}
#endif
