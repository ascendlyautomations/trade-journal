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

    static func logOpenPipeline(
        conversationID: String,
        stage: String,
        remoteReturned: Int?,
        requestedPageSize: Int?,
        cursor: String?,
        grdbOrDiskStored: Int?,
        grdbOrDiskQueried: Int?,
        viewModelBefore: Int? = nil,
        viewModelAfter: Int? = nil,
        viewModelCount: Int? = nil,
        renderedCount: Int?,
        hasMoreOlder: Bool?,
        oldestMessageID: String? = nil,
        newestMessageID: String? = nil,
        initialScrollPhase: String? = nil,
        remoteMessageIDsSample: String? = nil
    ) {
        let vmAfter = viewModelAfter ?? viewModelCount
        let vmBefore = viewModelBefore ?? viewModelCount
        logger.debug(
            """
            thread.open conversation=\(conversationID, privacy: .public) stage=\(stage, privacy: .public) \
            remote=\(remoteReturned.map(String.init) ?? "nil", privacy: .public) \
            remoteIDs=\(remoteMessageIDsSample ?? "nil", privacy: .public) \
            pageSize=\(requestedPageSize.map(String.init) ?? "nil", privacy: .public) \
            cursor=\(cursor ?? "nil", privacy: .public) \
            diskStored=\(grdbOrDiskStored.map(String.init) ?? "nil", privacy: .public) \
            diskQueried=\(grdbOrDiskQueried.map(String.init) ?? "nil", privacy: .public) \
            viewModelBefore=\(vmBefore.map(String.init) ?? "nil", privacy: .public) \
            viewModelAfter=\(vmAfter.map(String.init) ?? "nil", privacy: .public) \
            rendered=\(renderedCount.map(String.init) ?? "nil", privacy: .public) \
            oldest=\(oldestMessageID ?? "nil", privacy: .public) \
            newest=\(newestMessageID ?? "nil", privacy: .public) \
            initialScroll=\(initialScrollPhase ?? "nil", privacy: .public) \
            hasMoreOlder=\(hasMoreOlder.map { $0 ? "true" : "false" } ?? "nil", privacy: .public)
            """
        )
    }
}
#endif
