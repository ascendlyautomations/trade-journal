import Foundation
import OSLog

#if DEBUG
nonisolated enum TradeDetailTelemetry {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradeDetail")

    static func load(tradeID: TradeID, viewer: String?) {
        log.debug("[TradeDetail][Load] tradeID=\(tradeID.rawValue, privacy: .public) viewer=\(viewer ?? "anon", privacy: .public)")
    }

    static func cacheHit(tradeID: TradeID, viewer: String?) {
        log.debug("[TradeDetail][CacheHit] tradeID=\(tradeID.rawValue, privacy: .public) viewer=\(viewer ?? "anon", privacy: .public)")
    }

    static func singleFlight(tradeID: TradeID, viewer: String?) {
        log.debug("[TradeDetail][SingleFlight] tradeID=\(tradeID.rawValue, privacy: .public) viewer=\(viewer ?? "anon", privacy: .public)")
    }

    static func network(
        tradeID: TradeID,
        viewer: String?,
        bytes: Int?,
        elapsedMs: Double?
    ) {
        log.debug(
            "[TradeDetail][Network] tradeID=\(tradeID.rawValue, privacy: .public) viewer=\(viewer ?? "anon", privacy: .public) bytes=\(bytes ?? -1) elapsedMs=\(elapsedMs ?? -1, privacy: .public)"
        )
    }

    static func loaded(tradeID: TradeID, viewer: String?, elapsedMs: Double) {
        log.debug(
            "[TradeDetail][Loaded] tradeID=\(tradeID.rawValue, privacy: .public) viewer=\(viewer ?? "anon", privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
    }

    static func evict(tradeID: TradeID, reason: String) {
        log.debug("[TradeDetail][Evict] tradeID=\(tradeID.rawValue, privacy: .public) reason=\(reason, privacy: .public)")
    }

    static func fallback(tradeID: TradeID, reason: String) {
        log.debug("[TradeDetail][Fallback] tradeID=\(tradeID.rawValue, privacy: .public) reason=\(reason, privacy: .public)")
    }

    static func unauthorized(tradeID: TradeID, viewer: String?) {
        log.debug("[TradeDetail][Unauthorized] tradeID=\(tradeID.rawValue, privacy: .public) viewer=\(viewer ?? "anon", privacy: .public)")
    }
}
#endif
