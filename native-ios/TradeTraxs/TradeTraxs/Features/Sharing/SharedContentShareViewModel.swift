import Foundation
import Observation

@Observable
@MainActor
final class SharedContentShareViewModel {
    enum RecipientScope: Equatable {
        case messages
        case rooms
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case sending
        case sent
        case failed(String)
    }

    let target: SharedContentShareTarget

    private(set) var phase: Phase = .idle
    private(set) var conversations: [Conversation] = []
    private(set) var rooms: [TradeRoom] = []
    private(set) var sendErrorMessage: String?

    var selectedConversationIDs: Set<ConversationID> = []
    var selectedRoomIDs: Set<RoomID> = []
    var accompanyingMessage = ""

    private let messagesRepo: any MessageRepository
    private let roomsRepo: any RoomRepository
    private let session: any SessionProviding
    private let inboxStore: MessagesInboxStore
    private let detailCache: DetailPresentationCache

    init(
        target: SharedContentShareTarget,
        messagesRepo: any MessageRepository,
        roomsRepo: any RoomRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.target = target
        self.messagesRepo = messagesRepo
        self.roomsRepo = roomsRepo
        self.session = session
        self.detailCache = detailCache
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
    }

    var hasSelection: Bool {
        !selectedConversationIDs.isEmpty || !selectedRoomIDs.isEmpty
    }

    var selectedDestinationCount: Int {
        selectedConversationIDs.count + selectedRoomIDs.count
    }

    func clearSendError() {
        sendErrorMessage = nil
    }

    func isConversationSelected(_ id: ConversationID) -> Bool {
        selectedConversationIDs.contains(id)
    }

    func isRoomSelected(_ id: RoomID) -> Bool {
        selectedRoomIDs.contains(id)
    }

    func toggleConversationSelection(_ conversation: Conversation) {
        guard phase != .sending else { return }
        ExperienceHaptics.play(.selection)
        if selectedConversationIDs.contains(conversation.id) {
            selectedConversationIDs.remove(conversation.id)
        } else {
            selectedConversationIDs.insert(conversation.id)
        }
    }

    func toggleRoomSelection(_ room: TradeRoom) {
        guard phase != .sending else { return }
        ExperienceHaptics.play(.selection)
        if selectedRoomIDs.contains(room.id) {
            selectedRoomIDs.remove(room.id)
        } else {
            selectedRoomIDs.insert(room.id)
        }
    }

    var externalShareText: String { target.externalShareText }

    func loadRecipients(for scope: RecipientScope) async {
        phase = .loading
        sendErrorMessage = nil
        defer {
            if phase == .loading { phase = .loaded }
        }

        if inboxStore.hasLoaded, scope == .messages, !inboxStore.visibleConversations.isEmpty {
            conversations = inboxStore.visibleConversations
            phase = .loaded
            return
        }
        if inboxStore.hasLoadedRooms, scope == .rooms, !inboxStore.rooms.isEmpty {
            rooms = inboxStore.rooms
            phase = .loaded
            return
        }

        guard let viewerID = await session.currentUserID else {
            phase = .failed("Sign in to share this content.")
            return
        }

        do {
            switch scope {
            case .messages:
                let result = try await messagesRepo.conversations(page: PageRequest(limit: 80))
                conversations = result.items
            case .rooms:
                let page = try await roomsRepo.memberRooms(
                    for: ProfileID(viewerID.rawValue),
                    page: PageRequest(limit: 80)
                )
                rooms = page.items
            }
            phase = .loaded
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }

    /// Sends optional accompanying text (first) then shared content to every selected destination.
    func sendToSelected() async -> Bool {
        guard phase != .sending, hasSelection, let viewerID = await session.currentUserID else { return false }

        phase = .sending
        sendErrorMessage = nil

        let profileID = ProfileID(viewerID.rawValue)
        let trimmed = accompanyingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let accompanyingText = trimmed.isEmpty ? nil : trimmed

        SharedContentShareSeeder.seed(
            target: target,
            detailCache: detailCache,
            feedSessionStore: FeedSessionStore.shared,
            viewerID: profileID
        )

        var failures: [String] = []
        var successCount = 0

        let selectedConversations = conversations.filter { selectedConversationIDs.contains($0.id) }
        for conversation in selectedConversations {
            if await sendBundle(to: conversation, accompanyingText: accompanyingText, viewerID: profileID) {
                selectedConversationIDs.remove(conversation.id)
                successCount += 1
            } else {
                failures.append(conversation.title ?? "Conversation")
            }
        }

        let selectedRooms = rooms.filter { selectedRoomIDs.contains($0.id) }
        for room in selectedRooms {
            if await sendBundle(to: room, accompanyingText: accompanyingText, viewerID: profileID) {
                selectedRoomIDs.remove(room.id)
                successCount += 1
            } else {
                failures.append(room.name)
            }
        }

        if failures.isEmpty {
            accompanyingMessage = ""
            phase = .sent
            ExperienceHaptics.play(.messageSent)
            return true
        }

        phase = .loaded
        if successCount > 0 {
            if failures.count == 1 {
                sendErrorMessage =
                    "Sent to \(successCount) destination\(successCount == 1 ? "" : "s"). Couldn't send to \(failures[0])."
            } else {
                sendErrorMessage =
                    "Sent to \(successCount) destination\(successCount == 1 ? "" : "s"). \(failures.count) couldn't be sent."
            }
            ExperienceHaptics.play(.warning)
        } else {
            sendErrorMessage = sendErrorMessage ?? "Couldn't send. Try again."
            ExperienceHaptics.play(.error)
        }
        return false
    }

    // MARK: - DM bundle (text → shared content)

    private func sendBundle(
        to conversation: Conversation,
        accompanyingText: String?,
        viewerID: ProfileID
    ) async -> Bool {
        if let text = accompanyingText {
            let sent = await sendTextMessage(text, to: conversation, viewerID: viewerID)
            if !sent { return false }
        }
        return await sendSharedContent(to: conversation, viewerID: viewerID)
    }

    private func sendTextMessage(
        _ text: String,
        to conversation: Conversation,
        viewerID: ProfileID
    ) async -> Bool {
        let optimistic = Message(
            id: MessageID("temp-\(UUID().uuidString)"),
            conversationID: conversation.id,
            senderProfileID: viewerID,
            kind: .text,
            body: text,
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true,
            sharedContent: nil
        )

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversation.id)
        {
            deliverOutbound(message: optimistic, conversation: conversation, viewerID: viewerID)
            return true
        }

        do {
            let saved = try await messagesRepo.send(optimistic)
            deliverOutbound(message: saved, conversation: conversation, viewerID: viewerID)
            return true
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    private func sendSharedContent(
        to conversation: Conversation,
        viewerID: ProfileID
    ) async -> Bool {
        let optimistic = makeOptimisticSharedMessage(
            conversationID: conversation.id,
            viewerID: viewerID
        )

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversation.id)
        {
            deliverOutbound(message: optimistic, conversation: conversation, viewerID: viewerID)
            return true
        }

        do {
            let saved = try await messagesRepo.send(optimistic)
            deliverOutbound(message: saved, conversation: conversation, viewerID: viewerID)
            return true
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    // MARK: - Room bundle (text → shared content)

    private func sendBundle(
        to room: TradeRoom,
        accompanyingText: String?,
        viewerID: ProfileID
    ) async -> Bool {
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || room.id.rawValue.hasPrefix("dev-")
        {
            return true
        }

        do {
            let channels = try await roomsRepo.channels(roomID: room.id)
            guard let channel = channels.first(where: \.isGeneral) ?? channels.first else {
                sendErrorMessage = "\(room.name) has no channels yet."
                return false
            }

            if let text = accompanyingText {
                let sent = await sendRoomTextMessage(
                    text,
                    room: room,
                    channelID: channel.id,
                    viewerID: viewerID
                )
                if !sent { return false }
            }

            return await sendRoomSharedContent(
                room: room,
                channelID: channel.id,
                viewerID: viewerID
            )
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    private func sendRoomTextMessage(
        _ text: String,
        room: TradeRoom,
        channelID: RoomChannelID,
        viewerID: ProfileID
    ) async -> Bool {
        let tempID = RoomMessageID("temp-\(UUID().uuidString)")
        let payload = RoomMessage(
            id: tempID,
            roomID: room.id,
            senderProfileID: viewerID,
            body: text,
            attachedTradeID: nil,
            media: [],
            parentMessageID: nil,
            channelID: channelID,
            isPinned: false,
            createdAt: .now
        )

        do {
            let saved = try await roomsRepo.send(payload)
            let display = RoomMessageMapping.displayMessage(from: saved)
            deliverRoomOutbound(message: display, room: room, channelID: channelID, viewerID: viewerID)
            return true
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    private func sendRoomSharedContent(
        room: TradeRoom,
        channelID: RoomChannelID,
        viewerID: ProfileID
    ) async -> Bool {
        let payload = makeRoomMessage(
            room: room,
            channelID: channelID,
            viewerID: viewerID
        )

        do {
            let saved = try await roomsRepo.send(payload)
            let display = RoomMessageMapping.displayMessage(from: saved)
            if let reference = display.sharedContent {
                SharedContentShareSeeder.seed(
                    reference: reference,
                    detailCache: detailCache,
                    feedSessionStore: FeedSessionStore.shared,
                    viewerID: viewerID
                )
            }
            deliverRoomOutbound(message: display, room: room, channelID: channelID, viewerID: viewerID)
            return true
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    // MARK: - Message builders

    private func makeOptimisticSharedMessage(
        conversationID: ConversationID,
        viewerID: ProfileID
    ) -> Message {
        let reference = target.reference
        let attachments: [MessageAttachment]
        if reference.messageKind == .tradeShare, case .trade(let tradeID) = reference {
            attachments = [
                MessageAttachment(
                    id: tradeID.rawValue,
                    media: MediaReference(id: tradeID.rawValue, kind: .file, altText: "Shared trade"),
                    tradeID: tradeID
                ),
            ]
        } else {
            attachments = []
        }

        return Message(
            id: MessageID("temp-\(UUID().uuidString)"),
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: reference.messageKind,
            body: nil,
            attachments: attachments,
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true,
            sharedContent: reference
        )
    }

    private func makeRoomMessage(
        room: TradeRoom,
        channelID: RoomChannelID,
        viewerID: ProfileID
    ) -> RoomMessage {
        if let tradeID = target.roomTradeID {
            return RoomMessage(
                id: RoomMessageID("temp-\(UUID().uuidString)"),
                roomID: room.id,
                senderProfileID: viewerID,
                body: "Shared a trade",
                attachedTradeID: tradeID,
                media: [],
                parentMessageID: nil,
                channelID: channelID,
                isPinned: false,
                createdAt: .now
            )
        }

        let encoded = SharedContentRoomMessageSupport.encode(reference: target.reference)
        return RoomMessage(
            id: RoomMessageID("temp-\(UUID().uuidString)"),
            roomID: room.id,
            senderProfileID: viewerID,
            body: encoded,
            attachedTradeID: nil,
            media: [],
            parentMessageID: nil,
            channelID: channelID,
            isPinned: false,
            createdAt: .now,
            shareType: target.reference.messageType
        )
    }

    // MARK: - Outbound delivery

    private func deliverOutbound(
        message: Message,
        conversation: Conversation,
        viewerID: ProfileID
    ) {
        if let reference = message.sharedContent {
            SharedContentShareSeeder.seed(
                reference: reference,
                detailCache: detailCache,
                feedSessionStore: FeedSessionStore.shared,
                viewerID: viewerID
            )
        }
        patchInbox(with: message, conversation: conversation, viewerID: viewerID)
        SharedContentOutboundDelivery.post(
            SharedContentOutboundDelivery.Payload(
                destination: .dm(conversation.id),
                message: message
            )
        )
    }

    private func deliverRoomOutbound(
        message: Message,
        room: TradeRoom,
        channelID: RoomChannelID,
        viewerID: ProfileID
    ) {
        if let reference = message.sharedContent {
            SharedContentShareSeeder.seed(
                reference: reference,
                detailCache: detailCache,
                feedSessionStore: FeedSessionStore.shared,
                viewerID: viewerID
            )
        }
        SharedContentOutboundDelivery.post(
            SharedContentOutboundDelivery.Payload(
                destination: .room(room.id, channelID: channelID),
                message: message
            )
        )
    }

    private func patchInbox(with message: Message, conversation: Conversation, viewerID: ProfileID) {
        let isOpen = inboxStore.activeConversationID == message.conversationID
        inboxStore.patchFromMessage(
            message,
            viewerID: viewerID,
            conversationOpen: isOpen,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation,
            source: "sharedContentSend"
        )
        let patchedConversation =
            inboxStore.conversations.first(where: { $0.id == message.conversationID })
            ?? conversation
        ConversationThreadSessionStore.shared.patchMessages(
            viewerID: viewerID,
            conversationID: message.conversationID,
            incoming: [message],
            conversation: patchedConversation
        )
    }
}

extension SharedContentShareViewModel.RecipientScope: Identifiable {
    var id: String {
        switch self {
        case .messages: return "messages"
        case .rooms: return "rooms"
        }
    }
}
