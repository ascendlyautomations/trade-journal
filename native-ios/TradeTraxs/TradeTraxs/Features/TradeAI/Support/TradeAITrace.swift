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

    static func analysisFailed(status: Int, byteCount: Int, category: String) {
        log("analysis.failed status=\(status) bytes=\(byteCount) category=\(category)")
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

    private static func log(_ message: String) {
        let line = "[TradeAITrace] \(message)"
        logger.info("\(line, privacy: .public)")
    }
}
