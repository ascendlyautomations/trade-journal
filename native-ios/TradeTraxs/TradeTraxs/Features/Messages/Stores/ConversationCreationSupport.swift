import Foundation

nonisolated enum ConversationCreationSupport {
    static func directPairKey(_ a: ProfileID, _ b: ProfileID) -> String {
        DirectConversationPairIndex.pairKey(a, b)
    }

    @MainActor
    static func findExistingDirectLocally(
        viewerID: ProfileID,
        recipientID: ProfileID,
        inboxStore: MessagesInboxStore
    ) -> Conversation? {
        if let indexedID = DirectConversationPairIndex.shared.conversationID(
            viewerID: viewerID,
            recipientID: recipientID
        ) {
            if let match = inboxStore.conversations.first(where: { $0.id == indexedID && !$0.isGroup }) {
                return match
            }
            return nil
        }
        return findExistingDirectInInbox(viewerID: viewerID, recipientID: recipientID, inboxStore: inboxStore)
    }

    @MainActor
    static func findExistingDirectInInbox(
        viewerID: ProfileID,
        recipientID: ProfileID,
        inboxStore: MessagesInboxStore
    ) -> Conversation? {
        let target = Set([viewerID.rawValue.lowercased(), recipientID.rawValue.lowercased()])
        return inboxStore.conversations.first {
            guard !$0.isGroup, $0.participantProfileIDs.count == 2 else { return false }
            let participants = Set($0.participantProfileIDs.map { $0.rawValue.lowercased() })
            return participants == target
        }
    }

    static func buildDirectConversation(
        id: ConversationID,
        viewerID: ProfileID,
        recipient: Profile
    ) -> Conversation {
        Conversation(
            id: id,
            participantProfileIDs: [viewerID, recipient.id],
            title: recipient.displayName,
            peerUsername: recipient.username,
            avatar: recipient.avatar,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            isMuted: false,
            updatedAt: .distantPast
        )
    }

    static func buildGroupConversation(
        id: ConversationID,
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) -> Conversation {
        let participantIDs = [viewerID] + recipients.map(\.id)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedName?.isEmpty == false) ? trimmedName : fallbackGroupTitle(recipients: recipients)
        return Conversation(
            id: id,
            participantProfileIDs: participantIDs,
            title: title,
            peerUsername: nil,
            avatar: nil,
            isGroup: true,
            isPinned: false,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            isMuted: false,
            updatedAt: .distantPast
        )
    }

    /// Web-style participant-name title when no custom group name is provided.
    static func fallbackGroupTitle(recipients: [Profile]) -> String {
        let names = recipients.map(\.displayName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Group Chat" }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        }
        let prefix = names.prefix(2).joined(separator: ", ")
        return "\(prefix) + \(names.count - 2)"
    }

    static func mutationFlightKey(
        viewerID: ProfileID,
        recipientID: ProfileID
    ) -> String {
        "direct|\(directPairKey(viewerID, recipientID))"
    }

    static func groupMutationFlightKey(
        viewerID: ProfileID,
        participantIDs: [ProfileID]
    ) -> String {
        let sorted = ([viewerID] + participantIDs).map(\.rawValue).sorted().joined(separator: ",")
        return "group|\(sorted)"
    }

    @MainActor
    static func seedCanonicalState(
        viewerID: ProfileID,
        conversation: Conversation,
        profiles: [Profile],
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore
    ) {
        for profile in profiles {
            detailCache.seed(profile)
        }
        inboxStore.upsertConversation(conversation)
        if !conversation.isGroup {
            DirectConversationPairIndex.shared.register(conversation: conversation)
        }

        let cacheKey = ConversationThreadSessionStore.cacheKey(
            viewerID: viewerID,
            conversationID: conversation.id
        )
        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: cacheKey,
                conversation: conversation,
                messages: [],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 1
            )
        )
    }
}
