import Foundation

/// Explore Mode Messages inbox — local DMs only (viewer = ``DemoExperienceSupport/profileID``).
nonisolated enum DemoExploreInboxFixtures {
    static let tradeRoomConversationID = ConversationID("demo.explore.dm.traders")

    static func conversations(viewerID: ProfileID) -> [Conversation] {
        let now = Date()
        return [
            Conversation(
                id: tradeRoomConversationID,
                participantProfileIDs: [viewerID, DemoExploreTradeRoom.hostProfileID],
                title: DemoExploreTradeRoom.hostProfile().displayName,
                peerUsername: DemoExploreTradeRoom.hostProfile().username,
                avatar: DemoExploreTradeRoom.hostProfile().avatar,
                isGroup: false,
                isPinned: true,
                lastMessagePreview: "Tap View Trade Room to join the discussion.",
                lastMessageAt: now.addingTimeInterval(-600),
                unreadCount: 1,
                isMuted: false,
                updatedAt: now.addingTimeInterval(-600)
            ),
            Conversation(
                id: ConversationID("demo.explore.dm.ada"),
                participantProfileIDs: [viewerID, ProfileID("dev.follower.ada")],
                title: "Ada Lovelace",
                peerUsername: "ada",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "Did you log that MNQ session yet?",
                lastMessageAt: now.addingTimeInterval(-4_200),
                unreadCount: 0,
                isMuted: false,
                updatedAt: now.addingTimeInterval(-4_200)
            ),
            Conversation(
                id: ConversationID("demo.explore.dm.desk"),
                participantProfileIDs: [viewerID, ProfileID("dev.following.nq")],
                title: "NQ Desk",
                peerUsername: "nqdesk",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "You: Sharing my pre-market levels.",
                lastMessageAt: now.addingTimeInterval(-86_400),
                unreadCount: 0,
                isMuted: true,
                updatedAt: now.addingTimeInterval(-86_400)
            ),
        ]
    }

    static func profiles(for conversations: [Conversation], viewerID: ProfileID) -> [Profile] {
        let ids = Set(conversations.flatMap(\.participantProfileIDs)).subtracting([viewerID])
        return ids.compactMap { id in
            if id == DemoExploreTradeRoom.hostProfileID {
                return DemoExploreTradeRoom.hostProfile()
            }
            return FollowListFixtures.profile(id: id)
        }
    }

    static func messages(
        conversationID: ConversationID,
        viewerID: ProfileID,
        peerID: ProfileID
    ) -> [Message] {
        let now = Date()
        if conversationID == tradeRoomConversationID {
            return [
                Message(
                    id: MessageID("\(conversationID.rawValue)-1"),
                    conversationID: conversationID,
                    senderProfileID: DemoExploreTradeRoom.hostProfileID,
                    kind: .text,
                    body: "Welcome to Explore Mode — your journal stays on-device while Feed and Rooms use live public data.",
                    attachments: [],
                    replyToMessageID: nil,
                    createdAt: now.addingTimeInterval(-7_200),
                    isReadByViewer: true
                ),
                Message(
                    id: MessageID("\(conversationID.rawValue)-2"),
                    conversationID: conversationID,
                    senderProfileID: DemoExploreTradeRoom.hostProfileID,
                    kind: .text,
                    body: "Our community room TradeTraxs Traders is active with setups and recaps. Use View Trade Room below to peek inside.",
                    attachments: [],
                    replyToMessageID: nil,
                    createdAt: now.addingTimeInterval(-600),
                    isReadByViewer: false
                ),
            ]
        }
        return ConversationThreadFixtures.messages(
            conversationID: conversationID,
            viewerID: viewerID,
            peerID: peerID
        )
    }

    static func linkedTradeRoomID(for conversationID: ConversationID) -> RoomID? {
        conversationID == tradeRoomConversationID ? DemoExploreTradeRoom.roomID : nil
    }
}
