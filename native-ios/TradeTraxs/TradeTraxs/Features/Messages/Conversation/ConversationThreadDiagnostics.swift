import Foundation
import OSLog

#if DEBUG
/// DEBUG-only thread cache / delete diagnostics — message IDs and counts only, no bodies.
enum ConversationThreadDiagnostics {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "ConversationThread")

    static func logBatchDelete(requested: Int, succeeded: Int) {
        logger.debug("thread.delete.batch requested=\(requested, privacy: .public) succeeded=\(succeeded, privacy: .public)")
    }

    static func logThreadState(
        messages: Int,
        oldestID: String?,
        hasMore: Bool,
        context: String
    ) {
        logger.debug(
            "thread.state \(context, privacy: .public) messages=\(messages, privacy: .public) oldest=\(oldestID ?? "nil", privacy: .public) hasMore=\(hasMore, privacy: .public)"
        )
    }

    static func logCacheReopen(messages: Int, cursor: String?) {
        logger.debug(
            "thread.cache reopen messages=\(messages, privacy: .public) cursor=\(cursor ?? "nil", privacy: .public)"
        )
    }
}
#endif
