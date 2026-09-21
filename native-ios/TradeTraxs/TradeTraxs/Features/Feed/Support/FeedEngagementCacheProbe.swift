#if DEBUG
import Foundation
import OSLog

enum FeedEngagementCacheProbe {
    enum FeedSource: String, Sendable {
        case memory
        case disk
        case network
        case sessionSibling
    }

    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "FeedEngagementCache"
    )

    static func logRestore(
        source: FeedSource,
        summary: FeedEngagementCacheRestore.RestoreSummary,
        totalVisibleTargets: Int,
        missingAfterRestore: Int,
        networkFallbackScheduled: Bool
    ) {
        let avoided = max(0, totalVisibleTargets - missingAfterRestore)
        logger.debug(
            """
            [FeedEngagementCache] source=\(source.rawValue, privacy: .public) \
            restoredExplicit=\(summary.restoredFromExplicitFlag, privacy: .public) \
            restoredLegacy=\(summary.restoredLegacyImplicit, privacy: .public) \
            skippedIncomplete=\(summary.skippedIncomplete, privacy: .public) \
            missingAfterRestore=\(missingAfterRestore, privacy: .public) \
            networkFallback=\(networkFallbackScheduled, privacy: .public) \
            requestsAvoided≈\(networkFallbackScheduled ? avoided : avoided, privacy: .public)
            """
        )
    }
}
#else
enum FeedEngagementCacheProbe {
    enum FeedSource: String, Sendable {
        case memory
        case disk
        case network
        case sessionSibling
    }

    static func logRestore(
        source: FeedSource,
        summary: FeedEngagementCacheRestore.RestoreSummary,
        totalVisibleTargets: Int,
        missingAfterRestore: Int,
        networkFallbackScheduled: Bool
    ) {
        _ = (source, summary, totalVisibleTargets, missingAfterRestore, networkFallbackScheduled)
    }
}
#endif
