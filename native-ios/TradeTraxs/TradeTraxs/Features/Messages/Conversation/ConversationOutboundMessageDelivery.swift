import Foundation

/// Shared DM outbound path — internal share sheet, in-thread composer, story share.
@MainActor
enum ConversationOutboundMessageDelivery {
    struct SendContext {
        var conversation: Conversation
        var viewerID: ProfileID
        var messagesRepo: any MessageRepository
        var inboxStore: MessagesInboxStore
        var detailCache: DetailPresentationCache
    }

    /// Optimistic row first, then persisted server row — same reconciliation as Trade Rooms.
    static func send(
        message: Message,
        context: SendContext,
        skipNetwork: Bool
    ) async -> Result<Message, Error> {
        deliver(message: message, context: context)
        if skipNetwork {
            return .success(message)
        }
        do {
            let saved = try await context.messagesRepo.send(message)
            deliver(message: saved, context: context)
            return .success(saved)
        } catch {
            return .failure(error)
        }
    }

    static func deliver(message: Message, context: SendContext) {
        if let reference = message.sharedContent {
            SharedContentShareSeeder.seed(
                reference: reference,
                detailCache: context.detailCache,
                feedSessionStore: FeedSessionStore.shared,
                viewerID: context.viewerID
            )
        }
        let isOpen = context.inboxStore.activeConversationID == message.conversationID
        context.inboxStore.patchFromMessage(
            message,
            viewerID: context.viewerID,
            conversationOpen: isOpen,
            policy: .confirmedOutgoing,
            fallbackConversation: context.conversation,
            source: "sharedContentSend"
        )
        let patchedConversation =
            context.inboxStore.conversations.first(where: { $0.id == message.conversationID })
            ?? context.conversation
        ConversationThreadSessionStore.shared.patchMessages(
            viewerID: context.viewerID,
            conversationID: message.conversationID,
            incoming: [message],
            conversation: patchedConversation
        )
        let hydrationSnapshot = SharedContentHydrator.shareOutboundSnapshot(
            message: message,
            detailCache: context.detailCache,
            feedSessionStore: FeedSessionStore.shared,
            viewerID: context.viewerID,
            surface: .dm
        )
        SharedContentOutboundDelivery.post(
            SharedContentOutboundDelivery.Payload(
                destination: .dm(message.conversationID),
                message: message,
                hydrationSnapshot: hydrationSnapshot
            )
        )
    }
}
