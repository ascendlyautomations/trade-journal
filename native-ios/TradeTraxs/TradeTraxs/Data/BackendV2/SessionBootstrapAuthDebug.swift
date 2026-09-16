import Foundation
import OSLog

#if DEBUG
/// DEBUG-only session bootstrap auth diagnostics — never logs tokens.
@MainActor
enum SessionBootstrapAuthDebug {
    static var snapshotProvider: () -> (
        sessionPhase: String,
        tokenPresent: Bool,
        authGeneration: UInt64
    ) = { ("unknown", false, 0) }

    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "SessionBootstrapAuth"
    )

    static func requestStarted(authRequired: Bool) {
        let snap = snapshotProvider()
        logger.debug(
            """
            [SessionBootstrapAuth] request.started authRequired=\(authRequired, privacy: .public) \
            sessionPhase=\(snap.sessionPhase, privacy: .public) tokenPresent=\(snap.tokenPresent, privacy: .public) \
            authGeneration=\(snap.authGeneration, privacy: .public)
            """
        )
    }

    static func requestCompleted(responseStatus: Int?, classification: String) {
        let snap = snapshotProvider()
        let statusLabel = responseStatus.map(String.init) ?? "—"
        logger.debug(
            """
            [SessionBootstrapAuth] request.completed sessionPhase=\(snap.sessionPhase, privacy: .public) \
            tokenPresent=\(snap.tokenPresent, privacy: .public) authGeneration=\(snap.authGeneration, privacy: .public) \
            responseStatus=\(statusLabel, privacy: .public) classification=\(classification, privacy: .public)
            """
        )
    }
}
#else
@MainActor
enum SessionBootstrapAuthDebug {
    static func requestStarted(authRequired: Bool) {}
    static func requestCompleted(responseStatus: Int?, classification: String) {}
}
#endif
