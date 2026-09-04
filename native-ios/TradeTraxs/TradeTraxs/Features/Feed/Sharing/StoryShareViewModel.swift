import Foundation
import Observation

@Observable
@MainActor
final class StoryShareViewModel {
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

    let story: Story
    let ownerUsername: String?

    private(set) var phase: Phase = .idle
    private(set) var conversations: [Conversation] = []
    private(set) var rooms: [TradeRoom] = []
    private(set) var sendErrorMessage: String?

    private let messagesRepo: any MessageRepository
    private let roomsRepo: any RoomRepository
    private let session: any SessionProviding
    private let inboxStore: MessagesInboxStore

    init(
        story: Story,
        ownerUsername: String?,
        messagesRepo: any MessageRepository,
        roomsRepo: any RoomRepository,
        session: any SessionProviding,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.story = story
        self.ownerUsername = ownerUsername
        self.messagesRepo = messagesRepo
        self.roomsRepo = roomsRepo
        self.session = session
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
    }

    func clearSendError() {
        sendErrorMessage = nil
    }

    var externalShareText: String {
        let handle = ownerUsername.map { "@\($0)" } ?? "A trader"
        return "\(handle)'s story on TradeTraxs"
    }

    var encodedPayload: String {
        StoryShareMessageSupport.encode(
            storyID: story.id,
            imageURL: story.media.id,
            ownerID: story.authorProfileID,
            ownerUsername: ownerUsername
        )
    }

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
            phase = .failed("Sign in to share this story.")
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

    func send(to conversation: Conversation) async -> Bool {
        guard phase != .sending, let viewerID = await session.currentUserID else { return false }
        phase = .sending
        sendErrorMessage = nil
        defer {
            if phase == .sending { phase = .loaded }
        }

        let optimistic = Message(
            id: MessageID("temp-\(UUID().uuidString)"),
            conversationID: conversation.id,
            senderProfileID: ProfileID(viewerID.rawValue),
            kind: .storyShare,
            body: encodedPayload,
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )

        if ConversationThreadSupport.isLocalDevelopment(ProfileID(viewerID.rawValue))
            || ConversationThreadSupport.isLocalConversation(conversation.id)
        {
            patchInbox(with: optimistic, conversation: conversation, viewerID: ProfileID(viewerID.rawValue))
            phase = .sent
            ExperienceHaptics.play(.messageSent)
            return true
        }

        do {
            let saved = try await messagesRepo.send(optimistic)
            patchInbox(with: saved, conversation: conversation, viewerID: ProfileID(viewerID.rawValue))
            phase = .sent
            ExperienceHaptics.play(.messageSent)
            return true
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.error)
            return false
        }
    }

    func send(to room: TradeRoom) async -> Bool {
        guard phase != .sending, let viewerID = await session.currentUserID else { return false }
        phase = .sending
        sendErrorMessage = nil
        defer {
            if phase == .sending { phase = .loaded }
        }

        if MessagesInboxSupport.isLocalDevelopmentProfile(ProfileID(viewerID.rawValue))
            || room.id.rawValue.hasPrefix("dev-")
        {
            phase = .sent
            ExperienceHaptics.play(.messageSent)
            return true
        }

        do {
            let channels = try await roomsRepo.channels(roomID: room.id)
            guard let channel = channels.first(where: \.isGeneral) ?? channels.first else {
                sendErrorMessage = "This room has no channels yet."
                return false
            }

            let payload = RoomMessage(
                id: RoomMessageID("temp-\(UUID().uuidString)"),
                roomID: room.id,
                senderProfileID: ProfileID(viewerID.rawValue),
                body: encodedPayload,
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: channel.id,
                isPinned: false,
                createdAt: .now
            )
            _ = try await roomsRepo.send(payload)
            phase = .sent
            ExperienceHaptics.play(.messageSent)
            return true
        } catch {
            sendErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.error)
            return false
        }
    }

    private func patchInbox(with message: Message, conversation: Conversation, viewerID: ProfileID) {
        let isOpen = inboxStore.activeConversationID == message.conversationID
        inboxStore.patchFromMessage(
            message,
            viewerID: viewerID,
            conversationOpen: isOpen,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation,
            source: "storyShareSend"
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
