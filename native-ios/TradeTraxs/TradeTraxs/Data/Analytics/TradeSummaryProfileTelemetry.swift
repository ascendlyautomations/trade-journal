#if DEBUG
import Foundation
import OSLog

nonisolated enum TradeSummaryProfileTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeSummary.Profile")

    static func recordLoad(
        path: String,
        tradeCount: Int,
        responseBytes: Int?,
        networkMs: Int?
    ) {
        log.info(
            "[TradeSummary][ProfileLoad] path=\(path, privacy: .public) count=\(tradeCount, privacy: .public) bytes=\(responseBytes ?? -1, privacy: .public) netMs=\(networkMs ?? -1, privacy: .public)"
        )
    }

    static func recordPage(path: String, tradeCount: Int) {
        log.info(
            "[TradeSummary][ProfilePage] path=\(path, privacy: .public) count=\(tradeCount, privacy: .public)"
        )
    }

    static func recordCacheHit(tradeCount: Int) {
        log.info("[TradeSummary][ProfileCacheHit] count=\(tradeCount, privacy: .public)")
    }

    static func recordDecode(path: String, tradeCount: Int, skipped: Int) {
        log.info(
            "[TradeSummary][ProfileDecode] path=\(path, privacy: .public) count=\(tradeCount, privacy: .public) skipped=\(skipped, privacy: .public)"
        )
    }

    static func recordParity(
        v1Bytes: Int?,
        v2Bytes: Int?,
        idsMatch: Bool,
        orderMatch: Bool
    ) {
        log.info(
            "[TradeSummary][ProfileParity] v1Bytes=\(v1Bytes ?? -1, privacy: .public) v2Bytes=\(v2Bytes ?? -1, privacy: .public) ids=\(idsMatch, privacy: .public) order=\(orderMatch, privacy: .public)"
        )
    }

    static func recordPrivacyReject(reason: String) {
        log.info("[TradeSummary][ProfilePrivacyReject] reason=\(reason, privacy: .public)")
    }
}
#endif
