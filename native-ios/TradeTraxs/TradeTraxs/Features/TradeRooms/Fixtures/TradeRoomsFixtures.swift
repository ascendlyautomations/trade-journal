import Foundation

enum TradeRoomsFixtures {
    static let viewerID = ProfileID("dev.messages.viewer")
    static let deskRoomID = RoomID("dev-room-desk")
    static let riskRoomID = RoomID("dev-room-risk")

    static func rooms(ownerID: ProfileID = viewerID) -> [TradeRoom] {
        MessagesInboxFixtures.rooms(ownerID: ownerID)
    }

    static func room(id: RoomID, ownerID: ProfileID = viewerID) -> TradeRoom? {
        rooms(ownerID: ownerID).first { $0.id == id }
    }

    /// Fixture channels mirroring typical web `room_sections` for a desk room.
    static func channels(roomID: RoomID) -> [RoomChannel] {
        [
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-general"),
                roomID: roomID,
                name: "general",
                position: 0,
                allowMembersChat: true
            ),
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-trades"),
                roomID: roomID,
                name: "trades",
                position: 1,
                allowMembersChat: true
            ),
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-wins"),
                roomID: roomID,
                name: "wins",
                position: 2,
                allowMembersChat: true
            ),
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-education"),
                roomID: roomID,
                name: "education",
                position: 3,
                allowMembersChat: true
            ),
        ]
    }

    static func messages(
        roomID: RoomID,
        viewerID: ProfileID,
        channelID: RoomChannelID? = nil
    ) -> [RoomMessage] {
        let channels = channels(roomID: roomID)
        let general = channels.first { $0.isGeneral }?.id
        let trades = channels.first { $0.name.lowercased() == "trades" }?.id
        let wins = channels.first { $0.name.lowercased() == "wins" }?.id
        let peer = ProfileID("dev.follower.ada")
        let now = Date()
        let all: [RoomMessage] = [
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-m1"),
                roomID: roomID,
                senderProfileID: peer,
                body: "Watching the 15m FVG fill — liquidity resting above.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: general,
                isPinned: false,
                createdAt: now.addingTimeInterval(-3_600),
                reactions: [
                    RoomMessageReaction(
                        id: "dev-react-1",
                        messageID: RoomMessageID("\(roomID.rawValue)-m1"),
                        userID: peer,
                        reaction: "👍",
                        createdAt: now.addingTimeInterval(-3_500)
                    ),
                ]
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-m2"),
                roomID: roomID,
                senderProfileID: viewerID,
                body: "Same read. Waiting for displacement before entry.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: general,
                isPinned: false,
                createdAt: now.addingTimeInterval(-2_400)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-m3"),
                roomID: roomID,
                senderProfileID: peer,
                body: "Levels posted in the notes.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: RoomMessageID("\(roomID.rawValue)-m1"),
                channelID: general,
                isPinned: true,
                createdAt: now.addingTimeInterval(-900)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-m4"),
                roomID: roomID,
                senderProfileID: viewerID,
                body: "Shared a trade",
                attachedTradeID: TradeID("dev-trade-share-1"),
                media: [],
                parentMessageID: nil,
                channelID: trades,
                isPinned: false,
                createdAt: now.addingTimeInterval(-400)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-m5"),
                roomID: roomID,
                senderProfileID: peer,
                body: "Clean R-multiple on the London open.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: wins,
                isPinned: false,
                createdAt: now.addingTimeInterval(-200)
            ),
        ]
        guard let channelID else { return all }
        let channel = channels.first { $0.id == channelID }
        if channel?.isGeneral == true {
            return all.filter { $0.channelID == channelID || $0.channelID == nil }
        }
        return all.filter { $0.channelID == channelID }
    }

    static func members(room: TradeRoom, viewerID: ProfileID) -> [RoomMemberItem] {
        let ada = FollowListFixtures.profile(id: ProfileID("dev.follower.ada"))
        let owner = FollowListFixtures.profile(id: room.ownerProfileID)
            ?? makeViewerProfile(id: room.ownerProfileID, name: "Room Owner", username: "owner")
        var items: [RoomMemberItem] = [
            RoomMemberItem(
                profile: owner,
                role: .owner,
                joinedAt: room.createdAt,
                isOnline: true
            ),
        ]
        if let ada, ada.id != room.ownerProfileID {
            items.append(
                RoomMemberItem(
                    profile: ada,
                    role: .admin,
                    joinedAt: room.createdAt.addingTimeInterval(86_400),
                    isOnline: false
                )
            )
        }
        if viewerID != room.ownerProfileID {
            let viewer = FollowListFixtures.profile(id: viewerID)
                ?? makeViewerProfile(id: viewerID, name: "You", username: "you")
            items.append(
                RoomMemberItem(
                    profile: viewer,
                    role: .member,
                    joinedAt: .now.addingTimeInterval(-172_800),
                    isOnline: true
                )
            )
        }
        return items
    }

    private static func makeViewerProfile(id: ProfileID, name: String, username: String) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: username,
            displayName: name,
            bio: nil,
            avatar: nil,
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Fixture active presence for DEBUG trade rooms (web demo parity).
    static func activePresenceWireUsers(viewerID: ProfileID?) -> [RoomPresenceWireUser] {
        let now = ISO8601DateFormatter().string(from: Date())
        var users: [RoomPresenceWireUser] = []
        if let viewerID {
            let viewer = FollowListFixtures.profile(id: viewerID)
                ?? makeViewerProfile(id: viewerID, name: "You", username: "you")
            users.append(
                RoomPresenceWireUser(
                    userID: viewerID.rawValue,
                    username: viewer.username,
                    avatarURL: viewer.avatar?.id,
                    enteredAt: now
                )
            )
        }
        if let ada = FollowListFixtures.profile(id: ProfileID("dev.follower.ada")) {
            users.append(
                RoomPresenceWireUser(
                    userID: ada.id.rawValue,
                    username: ada.username,
                    avatarURL: ada.avatar?.id,
                    enteredAt: now
                )
            )
        }
        return users
    }

    static func seedInbox(_ store: MessagesInboxStore, viewerID: ProfileID = viewerID) {
        MessagesInboxFixtures.seedStore(store, viewerID: viewerID)
    }
}

struct RoomMemberItem: Identifiable, Hashable, Sendable {
    var id: ProfileID { profile.id }
    var profile: Profile
    var role: RoomMemberRole
    var joinedAt: Date?
    var isOnline: Bool
}
