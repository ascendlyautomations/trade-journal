import Foundation
import OSLog

/// Privacy-safe Trade AI pipeline tracing, search console for `[TradeAITrace]`.
nonisolated enum TradeAITrace {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "TradeAI"
    )

    static func analysisStarted() {
        log("analysis.started")
    }

    static func analysisResponse(status: Int, byteCount: Int) {
        log("analysis.response status=\(status) bytes=\(byteCount)")
    }

    static func analysisDecoded() {
        log("analysis.decoded")
    }

    static func analysisFailed(
        status: Int,
        byteCount: Int,
        category: String,
        backendCode: String? = nil
    ) {
        if let backendCode, !backendCode.isEmpty {
            log("analysis.failed status=\(status) bytes=\(byteCount) category=\(category) code=\(backendCode)")
        } else {
            log("analysis.failed status=\(status) bytes=\(byteCount) category=\(category)")
        }
    }

    static func persistenceStarted(rowCount: Int, payloadType: String) {
        log("persistence.started rows=\(rowCount) payloadType=\(payloadType)")
    }

    static func persistenceCompleted(rowCount: Int) {
        log("persistence.completed rows=\(rowCount)")
    }

    static func persistenceFailed(error: Error) {
        let summary = String(describing: error).prefix(160)
        log("persistence.failed error=\(summary)")
    }

    static func tradeTurnResponse(status: Int, byteCount: Int) {
        log("tradeTurn.response status=\(status) bytes=\(byteCount)")
    }

    static func tradeTurnDecodeFailed(status: Int, byteCount: Int, category: String) {
        log("tradeTurn.decodeFailed status=\(status) bytes=\(byteCount) category=\(category)")
    }

    static func tradeTurnMapped(
        status: Int,
        byteCount: Int,
        decoded: Bool,
        replyLength: Int,
        shouldPersist: Bool,
        backendCode: String?,
        analysisSucceeded: Bool
    ) {
        let code = backendCode ?? "none"
        log(
            """
            tradeTurn.mapped status=\(status) bytes=\(byteCount) decoded=\(decoded) \
            replyLen=\(replyLength) shouldPersist=\(shouldPersist) code=\(code) \
            success=\(analysisSucceeded)
            """
        )
    }

    static func conversationHistoryLoaded(
        tradeScoped: Bool,
        status: Int,
        byteCount: Int,
        decoded: Bool,
        messageCount: Int
    ) {
        let scope = tradeScoped ? "trade" : "conversation"
        log(
            """
            conversation.history scope=\(scope) status=\(status) bytes=\(byteCount) \
            decoded=\(decoded) messages=\(messageCount)
            """
        )
    }

    static func persistTurnSucceeded(status: Int, byteCount: Int) {
        log("persistTurn.succeeded status=\(status) bytes=\(byteCount)")
    }

    static func persistTurnFailed(status: Int, byteCount: Int) {
        log("persistTurn.failed status=\(status) bytes=\(byteCount)")
    }

    static func persistTurnSkipped(reason: String) {
        log("persistTurn.skipped reason=\(reason)")
    }

    private static func log(_ message: String) {
        let line = "[TradeAITrace] \(message)"
        logger.info("\(line, privacy: .public)")
    }
}
