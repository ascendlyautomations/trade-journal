import Foundation
import os

#if DEBUG
nonisolated enum AnalyticsReconciliationProbe {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "AnalyticsRealtime"
    )

    static func signal(source: String, viewer: String, revision: Int64) {
        logger.debug(
            "[AnalyticsRealtime][Signal] source=\(source, privacy: .public) viewer=\(viewer, privacy: .public) revision=\(revision, privacy: .public)"
        )
    }

    static func coalesced(domain: String, revision: Int64, reason: String) {
        logger.debug(
            "[AnalyticsRealtime][Coalesced] domain=\(domain, privacy: .public) revision=\(revision, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    static func reconcileStart(domain: String, revision: Int64, scope: String) {
        logger.debug(
            "[AnalyticsRealtime][ReconcileStart] domain=\(domain, privacy: .public) revision=\(revision, privacy: .public) scope=\(scope, privacy: .public)"
        )
    }

    static func reconcileCommit(domain: String, revision: Int64, elapsedMs: Int) {
        logger.debug(
            "[AnalyticsRealtime][ReconcileCommit] domain=\(domain, privacy: .public) revision=\(revision, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
    }

    static func repair(reason: String, localRevision: Int64, serverRevision: Int64?) {
        let server = serverRevision.map { String($0) } ?? "unknown"
        logger.debug(
            "[AnalyticsRealtime][Repair] reason=\(reason, privacy: .public) localRevision=\(localRevision, privacy: .public) serverRevision=\(server, privacy: .public)"
        )
    }

    static func localScope(
        kind: String,
        viewer: String,
        oldDay: String?,
        newDay: String?,
        oldAccount: String?,
        newAccount: String?,
        oldMode: String?,
        newMode: String?
    ) {
        logger.debug(
            """
            [AnalyticsRealtime][LocalScope] kind=\(kind, privacy: .public) viewer=\(viewer, privacy: .public) \
            oldDay=\(oldDay ?? "-", privacy: .public) newDay=\(newDay ?? "-", privacy: .public) \
            oldAccount=\(oldAccount ?? "-", privacy: .public) newAccount=\(newAccount ?? "-", privacy: .public) \
            oldMode=\(oldMode ?? "-", privacy: .public) newMode=\(newMode ?? "-", privacy: .public)
            """
        )
    }

    static func uiApplied(domain: String, revision: Int64, elapsedMs: Int) {
        logger.debug(
            "[AnalyticsRealtime][UIApplied] domain=\(domain, privacy: .public) revision=\(revision, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
    }

    static func viewerReset(oldViewer: String?, newViewer: String?, generation: UInt64) {
        logger.debug(
            "[AnalyticsRealtime][ViewerReset] oldViewer=\(oldViewer ?? "nil", privacy: .public) newViewer=\(newViewer ?? "nil", privacy: .public) generation=\(generation, privacy: .public)"
        )
    }

    static func subscribe(viewer: String) {
        logger.debug(
            "[AnalyticsRealtime][Subscribe] viewer=\(viewer, privacy: .public)"
        )
    }

    static func subscribed(viewer: String) {
        logger.debug(
            "[AnalyticsRealtime][Subscribed] viewer=\(viewer, privacy: .public)"
        )
    }

    static func unsubscribe(viewer: String, reason: String) {
        logger.debug(
            "[AnalyticsRealtime][Unsubscribe] viewer=\(viewer, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    static func reconnect(viewer: String) {
        logger.debug(
            "[AnalyticsRealtime][Reconnect] viewer=\(viewer, privacy: .public)"
        )
    }

    static func repairRequest(reason: String) {
        logger.debug(
            "[AnalyticsRepair][Request] reason=\(reason, privacy: .public)"
        )
    }

    static func repairSuppressed(reason: String) {
        logger.debug(
            "[AnalyticsRepair][Suppressed] reason=\(reason, privacy: .public)"
        )
    }

    static func repairStart(reasons: String, localRevision: Int64, localSource: String) {
        logger.debug(
            "[AnalyticsRepair][Start] reasons=\(reasons, privacy: .public) localRevision=\(localRevision, privacy: .public) localSource=\(localSource, privacy: .public)"
        )
    }

    static func repairRPC(bytes: Int, elapsedMs: Int) {
        logger.debug(
            "[AnalyticsRepair][RPC] bytes=\(bytes, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
    }

    static func repairCurrent(localRevision: Int64, serverRevision: Int64) {
        logger.debug(
            "[AnalyticsRepair][Current] localRevision=\(localRevision, privacy: .public) serverRevision=\(serverRevision, privacy: .public)"
        )
    }

    static func repairStale(localRevision: Int64, serverRevision: Int64) {
        logger.debug(
            "[AnalyticsRepair][Stale] localRevision=\(localRevision, privacy: .public) serverRevision=\(serverRevision, privacy: .public)"
        )
    }

    static func repairAnomaly(localRevision: Int64, serverRevision: Int64) {
        logger.debug(
            "[AnalyticsRepair][Anomaly] localRevision=\(localRevision, privacy: .public) serverRevision=\(serverRevision, privacy: .public)"
        )
    }

    static func repairFailure(reason: String) {
        logger.debug(
            "[AnalyticsRepair][Failure] reason=\(reason, privacy: .public)"
        )
    }
}
#else
nonisolated enum AnalyticsReconciliationProbe {
    static func signal(source: String, viewer: String, revision: Int64) {}
    static func coalesced(domain: String, revision: Int64, reason: String) {}
    static func reconcileStart(domain: String, revision: Int64, scope: String) {}
    static func reconcileCommit(domain: String, revision: Int64, elapsedMs: Int) {}
    static func repair(reason: String, localRevision: Int64, serverRevision: Int64?) {}
    static func localScope(
        kind: String,
        viewer: String,
        oldDay: String?,
        newDay: String?,
        oldAccount: String?,
        newAccount: String?,
        oldMode: String?,
        newMode: String?
    ) {}

    static func uiApplied(domain: String, revision: Int64, elapsedMs: Int) {}

    static func viewerReset(oldViewer: String?, newViewer: String?, generation: UInt64) {}
    static func subscribe(viewer: String) {}
    static func subscribed(viewer: String) {}
    static func unsubscribe(viewer: String, reason: String) {}
    static func reconnect(viewer: String) {}
    static func repairRequest(reason: String) {}
    static func repairSuppressed(reason: String) {}
    static func repairStart(reasons: String, localRevision: Int64, localSource: String) {}
    static func repairRPC(bytes: Int, elapsedMs: Int) {}
    static func repairCurrent(localRevision: Int64, serverRevision: Int64) {}
    static func repairStale(localRevision: Int64, serverRevision: Int64) {}
    static func repairAnomaly(localRevision: Int64, serverRevision: Int64) {}
    static func repairFailure(reason: String) {}
}
#endif
