#if DEBUG
import Foundation
import os

enum ProfileTradesPaginationDiagnostics {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "profile.trades")

    static func started(profileID: ProfileID, cursor: String?) {
        log.info("profile.trades.loadMore started profile=\(profileID.rawValue, privacy: .public) cursorPresent=\((cursor != nil), privacy: .public)")
    }

    static func skipped(reason: String) {
        log.info("profile.trades.loadMore skipped reason=\(reason, privacy: .public)")
    }

    static func response(count: Int, hasMore: Bool) {
        log.info("profile.trades.loadMore response count=\(count, privacy: .public) hasMore=\(hasMore, privacy: .public)")
    }

    static func completed(appended: Int, hasMore: Bool) {
        log.info("profile.trades.loadMore completed appended=\(appended, privacy: .public) hasMore=\(hasMore, privacy: .public)")
    }

    static func cancelledOrStale(reason: String) {
        log.info("profile.trades.loadMore cancelled/stale reason=\(reason, privacy: .public)")
    }

    static func failed(message: String) {
        log.error("profile.trades.loadMore failed message=\(message, privacy: .public)")
    }
}
#endif
