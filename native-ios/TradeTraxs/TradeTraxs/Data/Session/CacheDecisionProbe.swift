import Foundation
import OSLog

#if DEBUG
/// DEBUG-only cache routing decisions for physical-device regression audits.
nonisolated enum CacheDecisionProbe {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "CacheDecision"
    )

    static func log(
        surface: String,
        cacheExists: Bool,
        cacheUsable: Bool,
        historyComplete: Bool? = nil,
        action: String,
        reason: String
    ) {
        let complete = historyComplete.map { String($0) } ?? "n/a"
        logger.debug(
            """
            [CacheDecision] surface=\(surface, privacy: .public) \
            cacheExists=\(cacheExists, privacy: .public) \
            cacheUsable=\(cacheUsable, privacy: .public) \
            historyComplete=\(complete, privacy: .public) \
            action=\(action, privacy: .public) \
            reason=\(reason, privacy: .public)
            """
        )
    }
}
#else
nonisolated enum CacheDecisionProbe {
    static func log(
        surface: String,
        cacheExists: Bool,
        cacheUsable: Bool,
        historyComplete: Bool? = nil,
        action: String,
        reason: String
    ) {}
}
#endif
