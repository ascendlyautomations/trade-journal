import Foundation

/// Deterministic Messages home content for DEBUG / development sessions.
enum MessagesInboxFixtures {
    static let viewerID = ProfileID("dev.messages.viewer")

    static func conversations(viewerID: ProfileID) -> [Conversation] {
        let now = Date()
        return [
            Conversation(
                id: ConversationID("dev-dm-ada"),
                participantProfileIDs: [viewerID, ProfileID("dev.follower.ada")],
                title: "Ada Lovelace",
                peerUsername: "ada",
                avatar: nil,
                isGroup: false,
                isPinned: true,
                lastMessagePreview: "Did you catch that NQ sweep?",
                lastMessageAt: now.addingTimeInterval(-120),
                unreadCount: 2,
                isMuted: false,
                updatedAt: now.addingTimeInterval(-120)
            ),
            Conversation(
                id: ConversationID("dev-dm-ict"),
                participantProfileIDs: [viewerID, ProfileID("dev.following.ict")],
                title: "Inner Circle",
                peerUsername: "ict",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "Sharing my London open checklist.",
                lastMessageAt: now.addingTimeInterval(-3_600),
                unreadCount: 0,
                isMuted: false,
                updatedAt: now.addingTimeInterval(-3_600)
            ),
            Conversation(
                id: ConversationID("dev-dm-nq"),
                participantProfileIDs: [viewerID, ProfileID("dev.following.nq")],
                title: "NQ Desk",
                peerUsername: "nqdesk",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "You: Locked in — R:R looks clean.",
                lastMessageAt: now.addingTimeInterval(-86_400),
                unreadCount: 0,
                isMuted: true,
                updatedAt: now.addingTimeInterval(-86_400)
            ),
            Conversation(
                id: ConversationID("dev-dm-risk"),
                participantProfileIDs: [viewerID, ProfileID("dev.following.risk")],
                title: "Risk First",
                peerUsername: "riskfirst",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "Muted alerts for the overnight session.",
                lastMessageAt: now.addingTimeInterval(-172_800),
                unreadCount: 1,
                isMuted: false,
                updatedAt: now.addingTimeInterval(-172_800)
            ),
        ]
    }

    static func profiles(for conversations: [Conversation], viewerID: ProfileID) -> [Profile] {
        let ids = Set(conversations.flatMap(\.participantProfileIDs)).subtracting([viewerID])
        return ids.compactMap { FollowListFixtures.profile(id: $0) }
    }

    static func rooms(ownerID: ProfileID) -> [TradeRoom] {
        [
            TradeRoom(
                id: RoomID("dev-room-desk"),
                ownerProfileID: ownerID,
                name: "NQ Desk Room",
                slug: "nq-desk",
                description: "Live levels and session notes.",
                image: nil,
                memberCount: 248,
                showsOnProfile: true,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            TradeRoom(
                id: RoomID("dev-room-risk"),
                ownerProfileID: ownerID,
                name: "Risk First",
                slug: "risk-first",
                description: "Position sizing and journal review.",
                image: nil,
                memberCount: 86,
                showsOnProfile: true,
                createdAt: Date(timeIntervalSince1970: 1_700_100_000)
            ),
        ]
    }

    static func roomPreviews() -> [RoomID: String] {
        [
            RoomID("dev-room-desk"): "Ada: Watching the 15m FVG fill.",
            RoomID("dev-room-risk"): "New member joined — say hello.",
        ]
    }

    static func roomUnread() -> [RoomID: Int] {
        [
            RoomID("dev-room-desk"): 5,
            RoomID("dev-room-risk"): 0,
        ]
    }

    static func seedStore(_ store: MessagesInboxStore, viewerID: ProfileID = viewerID) {
        let conversations = conversations(viewerID: viewerID)
        store.replaceConversations(conversations)
        store.replaceRooms(
            rooms(ownerID: viewerID),
            previews: roomPreviews(),
            unread: roomUnread()
        )
        store.seedLocalPresentation(
            pinned: [ConversationID("dev-dm-ada")],
            mutedConversations: [ConversationID("dev-dm-nq")],
            typing: [ConversationID("dev-dm-ict")],
            online: [ProfileID("dev.follower.ada"), ProfileID("dev.following.ict")],
            mutedRooms: [RoomID("dev-room-risk")]
        )
    }
}
