import Foundation
import OSLog

#if DEBUG
/// DEBUG-only instrumentation for cache freshness reconciliation.
nonisolated enum SyncStateProbe {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "SyncState"
    )

    nonisolated(unsafe) private static var dashboardBootstrapSkipped = 0
    nonisolated(unsafe) private static var sessionBootstrapSkipped = 0
    nonisolated(unsafe) private static var lastResult: String = ""
    nonisolated(unsafe) private static var lastResponseBytes: Int = 0

    static func logLocal(_ fingerprints: ViewerSyncStateFingerprints) {
        logger.debug(
            "[SyncState] local trades=\(fingerprints.trades.count, privacy: .public)/\(fingerprints.trades.checksum, privacy: .public) accounts=\(fingerprints.accounts.count, privacy: .public)/\(fingerprints.accounts.checksum, privacy: .public) profile=\(fingerprints.profile.checksum ?? "nil", privacy: .public)"
        )
    }

    static func logServer(_ fingerprints: ViewerSyncStateFingerprints) {
        logger.debug(
            "[SyncState] server trades=\(fingerprints.trades.count, privacy: .public)/\(fingerprints.trades.checksum, privacy: .public) accounts=\(fingerprints.accounts.count, privacy: .public)/\(fingerprints.accounts.checksum, privacy: .public) profile=\(fingerprints.profile.checksum ?? "nil", privacy: .public)"
        )
    }

    static func logUnchanged(dashboardBootstrapSkipped: Bool, sessionBootstrapSkipped: Bool) {
        lastResult = "UNCHANGED"
        if dashboardBootstrapSkipped { self.dashboardBootstrapSkipped += 1 }
        if sessionBootstrapSkipped { self.sessionBootstrapSkipped += 1 }
        logger.debug(
            "[SyncState] result=UNCHANGED dashboardBootstrap=\(dashboardBootstrapSkipped ? "SKIPPED" : "N/A", privacy: .public) sessionBootstrap=\(sessionBootstrapSkipped ? "SKIPPED" : "N/A", privacy: .public)"
        )
        ColdLaunchSummaryProbe.markFreshnessResult("UNCHANGED")
    }

    static func logChanged(domains: [ViewerSyncDomain], action: String) {
        lastResult = "CHANGED"
        DiskCacheIOProbe.noteReconciliation()
        let names = domains.map(\.rawValue).joined(separator: ",")
        logger.debug("[SyncState] changedDomains=\(names, privacy: .public) action=\(action, privacy: .public)")
        ColdLaunchSummaryProbe.markFreshnessResult("CHANGED")
    }

    static func logResponseBytes(_ bytes: Int) {
        lastResponseBytes = bytes
        logger.debug("[SyncState] responseBytes=\(bytes, privacy: .public)")
    }

    static func logFallback(_ reason: String) {
        logger.debug("[SyncState] fallback=\(reason, privacy: .public)")
        if reason.contains("preserved_cache") || reason.contains("sync_flag_off") || reason.contains("flags_off") {
            return
        }
        if reason.contains("sync_rpc_unavailable") {
            ColdLaunchSummaryProbe.markFreshnessResult("PRESERVED")
            return
        }
        if reason.contains("error") {
            ColdLaunchSummaryProbe.markFreshnessResult("FAILED")
        }
    }

    static func dashboardSkipCount() -> Int { dashboardBootstrapSkipped }
    static func sessionSkipCount() -> Int { sessionBootstrapSkipped }
    static func lastReconcileResult() -> String { lastResult }

    static func resetForTesting() {
        dashboardBootstrapSkipped = 0
        sessionBootstrapSkipped = 0
        lastResult = ""
        lastResponseBytes = 0
    }
}
#else
nonisolated enum SyncStateProbe {
    static func logLocal(_ fingerprints: ViewerSyncStateFingerprints) {}
    static func logServer(_ fingerprints: ViewerSyncStateFingerprints) {}
    static func logUnchanged(dashboardBootstrapSkipped: Bool, sessionBootstrapSkipped: Bool) {}
    static func logChanged(domains: [ViewerSyncDomain], action: String) {}
    static func logResponseBytes(_ bytes: Int) {}
    static func logFallback(_ reason: String) {}
    static func dashboardSkipCount() -> Int { 0 }
    static func sessionSkipCount() -> Int { 0 }
    static func lastReconcileResult() -> String { "" }
    static func resetForTesting() {}
}
#endif
