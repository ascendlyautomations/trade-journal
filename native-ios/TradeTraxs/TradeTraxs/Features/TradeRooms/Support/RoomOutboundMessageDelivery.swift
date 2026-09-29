import Foundation

/// Shared Trade Room outbound path — internal share, in-room composer, and story share.
@MainActor
enum RoomOutboundMessageDelivery {
    struct SendContext {
        var room: TradeRoom
        var channelID: RoomChannelID
        var viewerID: ProfileID
        var roomsRepo: any RoomRepository
        var detailCache: DetailPresentationCache
        var inboxStore: MessagesInboxStore
    }

    /// Persists via ``RoomRepository/send`` then delivers optimistic + saved display rows.
    static func send(
        payload: RoomMessage,
        context: SendContext,
        skipNetwork: Bool
    ) async -> Result<Message, Error> {
        let optimistic = RoomMessageMapping.displayMessage(from: payload)
        deliver(message: optimistic, context: context)

        if skipNetwork {
            return .success(optimistic)
        }

        do {
            let saved = try await context.roomsRepo.send(payload)
            let display = RoomMessageMapping.displayMessage(from: saved)
            deliver(message: display, context: context)
            return .success(display)
        } catch {
            #if DEBUG
            RoomMessageSendProbe.logFailed(
                RoomMessageSendProbe.Context(
                    roomID: payload.roomID.rawValue,
                    channelID: payload.channelID?.rawValue,
                    senderID: payload.senderProfileID.rawValue,
                    messageType: payload.shareType ?? (payload.attachedTradeID != nil ? "trade" : "text"),
                    hasReply: payload.parentMessageID != nil
                ),
                error: error
            )
            print(
                """
                [SharedContentRoomSend] FAILED room=\(payload.roomID.rawValue) \
                channel=\(payload.channelID?.rawValue ?? "nil") \
                type=\(payload.shareType ?? "trade/text") \
                error=\(ProfileSectionSupport.message(for: error))
                """
            )
            #endif
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
        patchInboxPreview(with: message, context: context)
        SocialPersistedCacheCoordinator.patchRoomChannelMessages(
            viewerID: context.viewerID,
            roomID: context.room.id,
            channelID: context.channelID,
            incoming: [message]
        )
        let hydrationSnapshot = SharedContentHydrator.shareOutboundSnapshot(
            message: message,
            detailCache: context.detailCache,
            feedSessionStore: FeedSessionStore.shared,
            viewerID: context.viewerID,
            surface: .tradeRoom
        )
        SharedContentOutboundDelivery.post(
            SharedContentOutboundDelivery.Payload(
                destination: .room(context.room.id, channelID: context.channelID),
                message: message,
                hydrationSnapshot: hydrationSnapshot
            )
        )
    }

    private static func patchInboxPreview(with message: Message, context: SendContext) {
        let preview: String = {
            if message.kind == .tradeShare {
                return "Shared a trade"
            }
            if let reference = message.sharedContent {
                return reference.inboxPreview
            }
            if message.attachments.isEmpty {
                let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (body?.isEmpty == false) ? body! : "New message"
            }
            let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (body?.isEmpty == false) ? body! : "Sent a photo"
        }()
        let roomsList =
            context.inboxStore.rooms.contains(where: { $0.id == context.room.id })
            ? context.inboxStore.rooms
            : context.inboxStore.rooms + [context.room]
        context.inboxStore.replaceRooms(
            roomsList,
            previews: [context.room.id: preview],
            activityAt: [context.room.id: message.createdAt],
            unread: [context.room.id: 0]
        )
    }
}
