import Foundation
import OSLog

#if DEBUG
/// DEBUG-only DM scroll lifecycle logging — IDs and counts only, no message bodies.
enum ConversationScrollDiagnostics {
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "ConversationScroll")

    static func logScrollAttempt(
        reason: String,
        conversationID: ConversationID,
        newestMessageID: MessageID?,
        firstMessageID: MessageID?,
        lastMessageID: MessageID?,
        targetID: String,
        targetExistsInTimeline: Bool,
        initialScrollPhase: String,
        phase: String,
        messageCount: Int,
        hasMoreOlder: Bool
    ) {
        logger.debug(
            """
            scroll.attempt reason=\(reason, privacy: .public) \
            conversation=\(conversationID.rawValue, privacy: .public) \
            newest=\(newestMessageID?.rawValue ?? "nil", privacy: .public) \
            first=\(firstMessageID?.rawValue ?? "nil", privacy: .public) \
            last=\(lastMessageID?.rawValue ?? "nil", privacy: .public) \
            target=\(targetID, privacy: .public) \
            targetInTimeline=\(targetExistsInTimeline, privacy: .public) \
            initialPhase=\(initialScrollPhase, privacy: .public) \
            phase=\(phase, privacy: .public) \
            count=\(messageCount, privacy: .public) \
            hasMoreOlder=\(hasMoreOlder, privacy: .public)
            """
        )
    }

    static func logCoordinatorCommand(
        reason: String,
        targetID: String?,
        animated: Bool,
        mode: String,
        initialScrollCompleted: Bool
    ) {
        logger.debug(
            """
            scroll.coordinator reason=\(reason, privacy: .public) \
            target=\(targetID ?? "nil", privacy: .public) \
            animated=\(animated, privacy: .public) \
            mode=\(mode, privacy: .public) \
            initialCompleted=\(initialScrollCompleted, privacy: .public)
            """
        )
    }

    static func logPaginationBlocked(reason: String) {
        logger.debug("scroll.pagination.blocked reason=\(reason, privacy: .public)")
    }

    static func logInitialScrollPhase(
        _ phase: String,
        conversationID: ConversationID,
        messageCount: Int,
        newestMessageID: MessageID?,
        pendingRichLayout: Bool = false
    ) {
        logger.debug(
            """
            scroll.initial.phase=\(phase, privacy: .public) \
            conversation=\(conversationID.rawValue, privacy: .public) \
            count=\(messageCount, privacy: .public) \
            newest=\(newestMessageID?.rawValue ?? "nil", privacy: .public) \
            pendingRichLayout=\(pendingRichLayout, privacy: .public)
            """
        )
    }
}
#endif
