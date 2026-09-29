import SwiftUI

/// Shared scroll commands for DM + Trade Room message lists (``ScrollViewReader`` + coordinator).
@MainActor
enum ConversationThreadScrollActions {
    static func scrollToLatest(
        proxy: ScrollViewProxy,
        newestMessageID: MessageID?,
        timelineContainsTarget: (String) -> Bool,
        animated: Bool,
        reduceMotion: Bool,
        reason: String,
        conversationID: ConversationID
    ) {
        let target = newestMessageID?.rawValue ?? ConversationScrollAnchorID.bottom
        _ = timelineContainsTarget(target)

        #if DEBUG
        logScrollAttemptIfNeeded(
            reason: reason,
            conversationID: conversationID,
            newestMessageID: newestMessageID,
            target: target,
            targetExists: timelineContainsTarget(target)
        )
        #endif

        let action = {
            proxy.scrollTo(target, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if animated {
                ExperienceMotion.withAnimation(
                    MotionCurve.easeOut.animation(duration: .fast),
                    reduceMotion: reduceMotion,
                    action
                )
            } else {
                action()
            }
        }
    }

    static func applyCoordinatorScrollCommand(
        proxy: ScrollViewProxy,
        coordinator: ConversationScrollCoordinator,
        appliedGeneration: inout UInt64,
        reduceMotion: Bool,
        isInitialScrollConfirmed: Bool
    ) {
        guard isInitialScrollConfirmed else { return }
        guard coordinator.scrollCommandGeneration != appliedGeneration else { return }
        guard let target = coordinator.desiredScrollPositionID else { return }
        appliedGeneration = coordinator.scrollCommandGeneration

        #if DEBUG
        ConversationScrollDiagnostics.logCoordinatorCommand(
            reason: "coordinator-command",
            targetID: target,
            animated: coordinator.desiredScrollAnimated,
            mode: String(describing: coordinator.mode),
            initialScrollCompleted: isInitialScrollConfirmed
        )
        #endif

        let apply = {
            proxy.scrollTo(target, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if coordinator.desiredScrollAnimated {
                ExperienceMotion.withAnimation(
                    MotionCurve.easeOut.animation(duration: .fast),
                    reduceMotion: reduceMotion,
                    apply
                )
            } else {
                apply()
            }
        }
    }

    #if DEBUG
    static func scrollToLatest(
        proxy: ScrollViewProxy,
        newestMessageID: MessageID?,
        timelineContainsTarget: (String) -> Bool,
        animated: Bool,
        reduceMotion: Bool,
        reason: String,
        conversationID: ConversationID,
        debugContext: ConversationScrollDiagnostics.ScrollAttemptContext
    ) {
        let target = newestMessageID?.rawValue ?? ConversationScrollAnchorID.bottom
        ConversationScrollDiagnostics.logScrollAttempt(
            reason: reason,
            conversationID: conversationID,
            newestMessageID: newestMessageID,
            firstMessageID: debugContext.firstMessageID,
            lastMessageID: debugContext.lastMessageID,
            targetID: target,
            targetExistsInTimeline: timelineContainsTarget(target),
            initialScrollPhase: debugContext.initialScrollPhase,
            phase: debugContext.phase,
            messageCount: debugContext.messageCount,
            hasMoreOlder: debugContext.hasMoreOlder
        )
        scrollToLatest(
            proxy: proxy,
            newestMessageID: newestMessageID,
            timelineContainsTarget: timelineContainsTarget,
            animated: animated,
            reduceMotion: reduceMotion,
            reason: reason,
            conversationID: conversationID
        )
    }

    private static func logScrollAttemptIfNeeded(
        reason: String,
        conversationID: ConversationID,
        newestMessageID: MessageID?,
        target: String,
        targetExists: Bool
    ) {}
    #endif
}

#if DEBUG
extension ConversationScrollDiagnostics {
    struct ScrollAttemptContext {
        var firstMessageID: MessageID?
        var lastMessageID: MessageID?
        var initialScrollPhase: String
        var phase: String
        var messageCount: Int
        var hasMoreOlder: Bool
    }
}
#endif
