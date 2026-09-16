import Foundation
import OSLog

#if DEBUG
/// DEBUG-only cold-launch restore timing — never logs tokens or credentials.
nonisolated enum AuthRestoreDebug {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "AuthRestore"
    )

    static func persistedSessionLoaded(expired: Bool, generation: UInt64) {
        logger.debug(
            "[AuthRestore] persistedSession.loaded expired=\(expired, privacy: .public) generation=\(generation, privacy: .public)"
        )
    }

    static func refreshStarted(generation: UInt64) {
        logger.debug("[AuthRestore] refresh.started generation=\(generation, privacy: .public)")
    }

    static func refreshSucceeded(durationMs: Int, generation: UInt64) {
        logger.debug(
            "[AuthRestore] refresh.succeeded durationMs=\(durationMs, privacy: .public) generation=\(generation, privacy: .public)"
        )
    }

    static func refreshFailed(classification: String, durationMs: Int, generation: UInt64) {
        logger.debug(
            "[AuthRestore] refresh.failed classification=\(classification, privacy: .public) durationMs=\(durationMs, privacy: .public) generation=\(generation, privacy: .public)"
        )
    }

    static func refreshTimedOut(durationMs: Int, generation: UInt64) {
        logger.debug(
            "[AuthRestore] refresh.timedOut durationMs=\(durationMs, privacy: .public) generation=\(generation, privacy: .public)"
        )
    }

    static func routeAuthenticated(generation: UInt64) {
        logger.debug("[AuthRestore] route.authenticated generation=\(generation, privacy: .public)")
    }

    static func routeUnauthenticated(generation: UInt64) {
        logger.debug("[AuthRestore] route.unauthenticated generation=\(generation, privacy: .public)")
    }

    static func routeRecoverableFailure(generation: UInt64) {
        logger.debug("[AuthRestore] route.recoverableFailure generation=\(generation, privacy: .public)")
    }
}
#else
nonisolated enum AuthRestoreDebug {
    static func persistedSessionLoaded(expired: Bool, generation: UInt64) {}
    static func refreshStarted(generation: UInt64) {}
    static func refreshSucceeded(durationMs: Int, generation: UInt64) {}
    static func refreshFailed(classification: String, durationMs: Int, generation: UInt64) {}
    static func refreshTimedOut(durationMs: Int, generation: UInt64) {}
    static func routeAuthenticated(generation: UInt64) {}
    static func routeUnauthenticated(generation: UInt64) {}
    static func routeRecoverableFailure(generation: UInt64) {}
}
#endif
