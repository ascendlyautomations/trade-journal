import Foundation
import OSLog

/// Privacy-safe Psychology Coach tracing. Filter console for `[PsychologyCoachTrace]`.
#if DEBUG
nonisolated enum PsychologyCoachTrace {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "PsychologyCoach"
    )

    static func requestStarted(
        mode: String,
        persistCachedOnly: Bool,
        bodyBytes: Int,
        hasConversationID: Bool
    ) {
        log(
            """
            request.started mode=\(mode) persistCachedOnly=\(persistCachedOnly) \
            bodyBytes=\(bodyBytes) hasConversationID=\(hasConversationID)
            """
        )
    }

    static func responseReceived(status: Int, byteCount: Int, contentType: String?) {
        let type = contentType ?? "unknown"
        log("request.response status=\(status) bytes=\(byteCount) contentType=\(type)")
    }

    static func decodeResult(decoded: Bool, category: String, replyLength: Int) {
        log("request.mapped decoded=\(decoded) category=\(category) replyLen=\(replyLength)")
    }

    static func requestFailed(status: Int, byteCount: Int, category: String) {
        log("request.failed status=\(status) bytes=\(byteCount) category=\(category)")
    }

    static func bootstrapSkipped(reason: String) {
        log("bootstrap.skipped reason=\(reason)")
    }

    static func bootstrapPhase(_ phase: String) {
        log("bootstrap.phase \(phase)")
    }

    static func bootstrapFailed(category: String) {
        log("bootstrap.failed category=\(category)")
    }

    private static func log(_ message: String) {
        let line = "[PsychologyCoachTrace] \(message)"
        logger.info("\(line, privacy: .public)")
    }
}
#else
nonisolated enum PsychologyCoachTrace {
    static func requestStarted(mode: String, persistCachedOnly: Bool, bodyBytes: Int, hasConversationID: Bool) {}
    static func responseReceived(status: Int, byteCount: Int, contentType: String?) {}
    static func decodeResult(decoded: Bool, category: String, replyLength: Int) {}
    static func requestFailed(status: Int, byteCount: Int, category: String) {}
    static func bootstrapSkipped(reason: String) {}
    static func bootstrapPhase(_ phase: String) {}
    static func bootstrapFailed(category: String) {}
}
#endif