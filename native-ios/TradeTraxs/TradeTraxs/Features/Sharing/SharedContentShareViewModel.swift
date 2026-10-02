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
    /// Resolved destination channel per selected Trade Room (required before send).
    private(set) var selectedRoomChannelIDs: [RoomID: RoomChannelID] = [:]
    private(set) var selectedRoomChannels: [RoomID: RoomChannel] = [:]
    var pendingRoomChannelPicker: RoomChannelPickerRequest?
    var accompanyingMessage = ""

    struct RoomChannelPickerRequest: Identifiable, Equatable {
        var id: RoomID { room.id }
        let room: TradeRoom
        var channels: [RoomChannel]
        var isLoadingChannels: Bool = false
    }

    private var cachedViewerProfileID: ProfileID?
    private var roomChannelsCache: [RoomID: [RoomChannel]] = [:]
    private var roomChannelFetchTasks: [RoomID: Task<Void, Never>] = [:]

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

    /// Send stays disabled until every selected Trade Room has a postable sub-room.
    var canSend: Bool {
        guard hasSelection else { return false }
        for roomID in selectedRoomIDs {
            guard selectedRoomChannelIDs[roomID] != nil else { return false }
        }
        return true
    }

    func selectedChannelDisplayTitle(for roomID: RoomID) -> String? {
        selectedRoomChannels[roomID]?.displayTitle
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

    /// Room row highlight while the sub-room sheet is open (before channel is confirmed).
    func isRoomSelectionPending(_ id: RoomID) -> Bool {
        pendingRoomChannelPicker?.room.id == id
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
        if selectedRoomIDs.contains(room.id) {
            ExperienceHaptics.play(.selection)
            if pendingRoomChannelPicker?.room.id == room.id {
                pendingRoomChannelPicker = nil
            }
            selectedRoomIDs.remove(room.id)
            selectedRoomChannelIDs.removeValue(forKey: room.id)
            selectedRoomChannels.removeValue(forKey: room.id)
            return
        }

        ExperienceHaptics.play(.selection)

        guard let profileID = resolvedViewerProfileID() else {
            Task { await resolveViewerAndSelectRoom(room) }
            return
        }

        if let postable = postableChannels(for: room, viewerID: profileID) {
            finishRoomSelection(room: room, postable: postable)
            return
        }

        pendingRoomChannelPicker = RoomChannelPickerRequest(
            room: room,
            channels: [],
            isLoadingChannels: true
        )
        startRoomChannelFetch(room: room, viewerID: profileID)
    }

    func confirmRoomChannelSelection(room: TradeRoom, channel: RoomChannel) {
        ExperienceHaptics.play(.selection)
        applyRoomChannelSelection(room: room, channel: channel)
        pendingRoomChannelPicker = nil
    }

    func cancelRoomChannelPicker() {
        pendingRoomChannelPicker = nil
    }

    private func resolvedViewerProfileID() -> ProfileID? {
        cachedViewerProfileID ?? inboxStore.persistedViewerID
    }

    private func postableChannels(for room: TradeRoom, viewerID: ProfileID) -> [RoomChannel]? {
        let raw: [RoomChannel]
        if let cached = roomChannelsCache[room.id] {
            raw = cached
        } else if let snapshot = SocialPersistedCacheCoordinator.restoreRoomSnapshot(
            viewerID: viewerID,
            roomID: room.id
        ) {
            roomChannelsCache[room.id] = snapshot.channels
            raw = snapshot.channels
        } else {
            return nil
        }
        let postable = SharedContentShareRoomChannelSupport.postableChannels(
            from: raw,
            room: room,
            viewerID: viewerID
        )
        return postable.isEmpty ? nil : postable
    }

    private func warmRoomChannelsCache(viewerID: ProfileID) {
        for room in rooms {
            _ = postableChannels(for: room, viewerID: viewerID)
        }
        Task { await prefetchRoomChannels(viewerID: viewerID) }
    }

    private func prefetchRoomChannels(viewerID: ProfileID) async {
        for room in rooms where roomChannelsCache[room.id] == nil {
            await fetchRoomChannels(room: room, viewerID: viewerID, applyToPendingPicker: false)
        }
    }

    private func startRoomChannelFetch(room: TradeRoom, viewerID: ProfileID) {
        roomChannelFetchTasks[room.id]?.cancel()
        roomChannelFetchTasks[room.id] = Task { [weak self] in
            guard let self else { return }
            await fetchRoomChannels(room: room, viewerID: viewerID, applyToPendingPicker: true)
            roomChannelFetchTasks.removeValue(forKey: room.id)
        }
    }

    private func fetchRoomChannels(
        room: TradeRoom,
        viewerID: ProfileID,
        applyToPendingPicker: Bool
    ) async {
        do {
            let channels = try await roomsRepo.channels(roomID: room.id)
            roomChannelsCache[room.id] = channels
            let postable = SharedContentShareRoomChannelSupport.postableChannels(
                from: channels,
                room: room,
                viewerID: viewerID
            )
            guard applyToPendingPicker else { return }
            guard pendingRoomChannelPicker?.room.id == room.id else { return }
            guard !postable.isEmpty else {
                pendingRoomChannelPicker = nil
                sendErrorMessage = "You can't post in any sub-room in \(room.name)."
                ExperienceHaptics.play(.warning)
                return
            }
            if postable.count == 1, let channel = postable.first {
                confirmRoomChannelSelection(room: room, channel: channel)
            } else {
                pendingRoomChannelPicker = RoomChannelPickerRequest(
                    room: room,
                    channels: postable,
                    isLoadingChannels: false
                )
            }
        } catch {
            guard applyToPendingPicker, pendingRoomChannelPicker?.room.id == room.id else { return }
            pendingRoomChannelPicker = nil
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    private func finishRoomSelection(room: TradeRoom, postable: [RoomChannel]) {
        if postable.count == 1, let channel = postable.first {
            applyRoomChannelSelection(room: room, channel: channel)
        } else {
            pendingRoomChannelPicker = RoomChannelPickerRequest(
                room: room,
                channels: postable,
                isLoadingChannels: false
            )
        }
    }

    private func resolveViewerAndSelectRoom(_ room: TradeRoom) async {
        guard let viewerID = await session.currentUserID else {
            sendErrorMessage = "Sign in to share this content."
            return
        }
        cachedViewerProfileID = ProfileID(viewerID.rawValue)
        toggleRoomSelection(room)
    }

    private func applyRoomChannelSelection(room: TradeRoom, channel: RoomChannel) {
        selectedRoomIDs.insert(room.id)
        selectedRoomChannelIDs[room.id] = channel.id
        selectedRoomChannels[room.id] = channel
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
            cachedViewerProfileID = inboxStore.persistedViewerID
            phase = .loaded
            return
        }
        if inboxStore.hasLoadedRooms, scope == .rooms, !inboxStore.rooms.isEmpty {
            rooms = inboxStore.rooms
            cachedViewerProfileID = inboxStore.persistedViewerID
            if let viewerID = resolvedViewerProfileID() {
                warmRoomChannelsCache(viewerID: viewerID)
            }
            phase = .loaded
            return
        }

        guard let viewerID = await session.currentUserID else {
            phase = .failed("Sign in to share this content.")
            return
        }
        cachedViewerProfileID = ProfileID(viewerID.rawValue)

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
                warmRoomChannelsCache(viewerID: ProfileID(viewerID.rawValue))
            }
            phase = .loaded
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }

    /// Sends optional accompanying text (first) then shared content to every selected destination.
    func sendToSelected() async -> Bool {
        guard phase != .sending, canSend, let viewerID = await session.currentUserID else {
            if hasSelection, !canSend {
                sendErrorMessage = "Choose a sub-room for each Trade Room before sending."
                ExperienceHaptics.play(.warning)
            }
            return false
        }

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
                selectedRoomChannelIDs.removeValue(forKey: room.id)
                selectedRoomChannels.removeValue(forKey: room.id)
                successCount += 1
            } else {
                failures.append(room.name)
            }
        }

        if failures.isEmpty, successCount > 0 {
            accompanyingMessage = ""
            phase = .sent
            ExperienceHaptics.play(.messageSent)
            return true
        }

        phase = .loaded
        if successCount == 0, failures.isEmpty {
            sendErrorMessage = "Couldn't send. Choose a destination and try again."
            ExperienceHaptics.play(.error)
            return false
        }
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

    // MARK: - DM bundle (shared content → optional text)

    private func sendBundle(
        to conversation: Conversation,
        accompanyingText: String?,
        viewerID: ProfileID
    ) async -> Bool {
        let sharedSent = await sendSharedContent(to: conversation, viewerID: viewerID)
        if !sharedSent { return false }
        if let text = accompanyingText {
            return await sendTextMessage(text, to: conversation, viewerID: viewerID)
        }
        return true
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

        let skipNetwork = ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversation.id)
        return await sendDMMessage(
            optimistic,
            conversation: conversation,
            viewerID: viewerID,
            skipNetwork: skipNetwork
        )
    }

    private func sendSharedContent(
        to conversation: Conversation,
        viewerID: ProfileID
    ) async -> Bool {
        let optimistic = makeOptimisticSharedMessage(
            conversationID: conversation.id,
            viewerID: viewerID
        )

        let skipNetwork = ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversation.id)
        return await sendDMMessage(
            optimistic,
            conversation: conversation,
            viewerID: viewerID,
            skipNetwork: skipNetwork
        )
    }

    private func sendDMMessage(
        _ message: Message,
        conversation: Conversation,
        viewerID: ProfileID,
        skipNetwork: Bool
    ) async -> Bool {
        let context = dmSendContext(conversation: conversation, viewerID: viewerID)
        switch await ConversationOutboundMessageDelivery.send(
            message: message,
            context: context,
            skipNetwork: skipNetwork
        ) {
        case .success:
            return true
        case .failure(let error):
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    private func dmSendContext(
        conversation: Conversation,
        viewerID: ProfileID
    ) -> ConversationOutboundMessageDelivery.SendContext {
        ConversationOutboundMessageDelivery.SendContext(
            conversation: conversation,
            viewerID: viewerID,
            messagesRepo: messagesRepo,
            inboxStore: inboxStore,
            detailCache: detailCache
        )
    }

    // MARK: - Room bundle (shared content → optional text)

    private func sendBundle(
        to room: TradeRoom,
        accompanyingText: String?,
        viewerID: ProfileID
    ) async -> Bool {
        guard let channelID = selectedRoomChannelIDs[room.id] else {
            sendErrorMessage = "Choose a sub-room in \(room.name) before sending."
            return false
        }

        let sharedSent = await sendRoomSharedContent(
            room: room,
            channelID: channelID,
            viewerID: viewerID
        )
        if !sharedSent { return false }

        if let text = accompanyingText {
            return await sendRoomTextMessage(
                text,
                room: room,
                channelID: channelID,
                viewerID: viewerID
            )
        }
        return true
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

        let context = roomSendContext(room: room, channelID: channelID, viewerID: viewerID)
        let skipNetwork = MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || room.id.rawValue.hasPrefix("dev-")

        switch await RoomOutboundMessageDelivery.send(
            payload: payload,
            context: context,
            skipNetwork: skipNetwork
        ) {
        case .success:
            return true
        case .failure(let error):
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

        let context = roomSendContext(room: room, channelID: channelID, viewerID: viewerID)
        let skipNetwork = MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || room.id.rawValue.hasPrefix("dev-")

        switch await RoomOutboundMessageDelivery.send(
            payload: payload,
            context: context,
            skipNetwork: skipNetwork
        ) {
        case .success:
            return true
        case .failure(let error):
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            return false
        }
    }

    private func roomSendContext(
        room: TradeRoom,
        channelID: RoomChannelID,
        viewerID: ProfileID
    ) -> RoomOutboundMessageDelivery.SendContext {
        RoomOutboundMessageDelivery.SendContext(
            room: room,
            channelID: channelID,
            viewerID: viewerID,
            roomsRepo: roomsRepo,
            detailCache: detailCache,
            inboxStore: inboxStore
        )
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

}

extension SharedContentShareViewModel.RecipientScope: Identifiable {
    var id: String {
        switch self {
        case .messages: return "messages"
        case .rooms: return "rooms"
        }
    }
}
