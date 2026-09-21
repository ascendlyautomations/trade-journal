#if DEBUG
import Foundation
import OSLog

/// Phase 8D — Journal TradeSummary load/decode/cache telemetry (Debug only).
nonisolated enum TradeSummaryJournalTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeSummary.Journal")

    static func recordLoad(
        path: String,
        tradeCount: Int,
        responseBytes: Int?,
        networkMs: Int?
    ) {
        log.info(
            "[TradeSummary][JournalLoad] path=\(path, privacy: .public) count=\(tradeCount, privacy: .public) bytes=\(responseBytes ?? -1, privacy: .public) netMs=\(networkMs ?? -1, privacy: .public)"
        )
    }

    static func recordPage(path: String, tradeCount: Int, responseBytes: Int?) {
        log.info(
            "[TradeSummary][JournalPage] path=\(path, privacy: .public) count=\(tradeCount, privacy: .public) bytes=\(responseBytes ?? -1, privacy: .public)"
        )
    }

    static func recordCacheHit(tradeCount: Int, restoreMs: Int?) {
        log.info(
            "[TradeSummary][JournalCacheHit] count=\(tradeCount, privacy: .public) restoreMs=\(restoreMs ?? -1, privacy: .public)"
        )
    }

    static func recordDecode(path: String, tradeCount: Int, skipped: Int) {
        log.info(
            "[TradeSummary][JournalDecode] path=\(path, privacy: .public) count=\(tradeCount, privacy: .public) skipped=\(skipped, privacy: .public)"
        )
    }

    static func recordSearch(path: String, queryLength: Int, resultCount: Int) {
        log.info(
            "[TradeSummary][JournalSearch] path=\(path, privacy: .public) qLen=\(queryLength, privacy: .public) results=\(resultCount, privacy: .public)"
        )
    }

    static func recordMutationPatch(tradeID: TradeID, action: String) {
        log.info(
            "[TradeSummary][JournalMutationPatch] id=\(tradeID.rawValue, privacy: .public) action=\(action, privacy: .public)"
        )
    }
}
#endif
