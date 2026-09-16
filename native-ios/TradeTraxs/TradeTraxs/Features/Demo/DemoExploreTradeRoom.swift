import Foundation

/// Local read-only Trade Room for Explore Mode — never synced to Supabase.
nonisolated enum DemoExploreTradeRoom {
    static let roomID = RoomID("demo.explore.trade-room")
    static let hostProfileID = ProfileID("demo.explore.community.host")

    static func isLocalRoom(_ id: RoomID) -> Bool { id == roomID }

    static func room(now: Date = Date()) -> TradeRoom {
        TradeRoom(
            id: roomID,
            ownerProfileID: hostProfileID,
            name: "TradeTraxs Traders",
            slug: "tradetraxs-traders",
            description: """
            A community room for traders to share setups, discuss the markets, and review \
            trades together.
            """,
            image: DemoExploreBundledAvatar.reference(assetName: DemoExploreIdentity.appLogoAssetName),
            memberCount: 1_842,
            showsOnProfile: true,
            isPrivate: false,
            category: .dayTrading,
            discoveryTags: ["futures", "day-trading", "journal"],
            joinPolicy: .open,
            rules: "Be respectful · No financial advice · Share process, not hype.",
            membersCanMessage: true,
            membersCanShareTrades: true,
            membersCanShareMedia: true,
            roomKind: .community,
            createdAt: now.addingTimeInterval(-86400 * 120)
        )
    }

    static func channels(roomID: RoomID = roomID) -> [RoomChannel] {
        [
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-general"),
                roomID: roomID,
                name: "general",
                position: 0,
                allowMembersChat: true
            ),
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-setups"),
                roomID: roomID,
                name: "setups",
                position: 1,
                allowMembersChat: true
            ),
            RoomChannel(
                id: RoomChannelID("\(roomID.rawValue)-recap"),
                roomID: roomID,
                name: "recap",
                position: 2,
                allowMembersChat: true
            ),
        ]
    }

    static func hostProfile() -> Profile {
        Profile(
            id: hostProfileID,
            userID: UserID(hostProfileID.rawValue),
            username: "tradetraxs_host",
            displayName: "TradeTraxs Community",
            bio: "Official community host for TradeTraxs Traders.",
            avatar: DemoExploreBundledAvatar.reference(assetName: DemoExploreIdentity.appLogoAssetName),
            traderType: .futures,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: true,
            createdAt: Date(timeIntervalSince1970: 1_730_000_000)
        )
    }

    static func memberProfiles(viewerID: ProfileID) -> [Profile] {
        var profiles = [hostProfile(), DemoExploreIdentity.profile()]
        if let ada = FollowListFixtures.profile(id: ProfileID("dev.follower.ada")) {
            profiles.append(ada)
        }
        if let ict = FollowListFixtures.profile(id: ProfileID("dev.following.ict")) {
            profiles.append(ict)
        }
        _ = viewerID
        return profiles
    }

    static func messages(
        roomID: RoomID = roomID,
        viewerID: ProfileID,
        channelID: RoomChannelID? = nil,
        now: Date = Date()
    ) -> [RoomMessage] {
        let channels = channels(roomID: roomID)
        let general = channels.first { $0.isGeneral }?.id
        let setups = channels.first { $0.name == "setups" }?.id
        let recap = channels.first { $0.name == "recap" }?.id
        let ada = ProfileID("dev.follower.ada")
        let sampleTradeID = DemoCanonicalDataset.trades().first?.id

        let all: [RoomMessage] = [
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-welcome"),
                roomID: roomID,
                senderProfileID: hostProfileID,
                body: "Welcome to TradeTraxs Traders — share your plan before the open and recap after the close.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: general,
                isPinned: true,
                createdAt: now.addingTimeInterval(-86_400 * 3)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-nq-levels"),
                roomID: roomID,
                senderProfileID: ada,
                body: "NQ: watching prior day high and the 15m FVG into London. No chase without displacement.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: setups,
                isPinned: false,
                createdAt: now.addingTimeInterval(-7_200)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-reply"),
                roomID: roomID,
                senderProfileID: hostProfileID,
                body: "Solid — post your screenshot when you're flat so we can review R-multiple.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: RoomMessageID("\(roomID.rawValue)-nq-levels"),
                channelID: setups,
                isPinned: false,
                createdAt: now.addingTimeInterval(-6_800)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-viewer-recap"),
                roomID: roomID,
                senderProfileID: viewerID,
                body: "Took one MNQ long off the sweep — stopped at BE after partial. Journaled in TradeTraxs.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: recap,
                isPinned: false,
                createdAt: now.addingTimeInterval(-3_600)
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-trade-share"),
                roomID: roomID,
                senderProfileID: ada,
                body: "Shared a trade",
                attachedTradeID: sampleTradeID,
                media: [],
                parentMessageID: nil,
                channelID: recap,
                isPinned: false,
                createdAt: now.addingTimeInterval(-1_800),
                reactions: [
                    RoomMessageReaction(
                        id: "demo-explore-react-1",
                        messageID: RoomMessageID("\(roomID.rawValue)-trade-share"),
                        userID: hostProfileID,
                        reaction: "🔥",
                        createdAt: now.addingTimeInterval(-1_700)
                    ),
                ]
            ),
            RoomMessage(
                id: RoomMessageID("\(roomID.rawValue)-close"),
                roomID: roomID,
                senderProfileID: hostProfileID,
                body: "Nice discipline on the BE management. See you in general for the NY open.",
                attachedTradeID: nil,
                media: [],
                parentMessageID: nil,
                channelID: general,
                isPinned: false,
                createdAt: now.addingTimeInterval(-900)
            ),
        ]

        guard let channelID else { return all }
        let channel = channels.first { $0.id == channelID }
        if channel?.isGeneral == true {
            return all.filter { $0.channelID == channelID || $0.channelID == nil }
        }
        return all.filter { $0.channelID == channelID }
    }

    static func members(viewerID: ProfileID) -> [RoomMemberItem] {
        let room = room()
        let host = hostProfile()
        var items: [RoomMemberItem] = [
            RoomMemberItem(
                profile: host,
                role: .owner,
                joinedAt: room.createdAt,
                isOnline: true
            ),
        ]
        if let ada = FollowListFixtures.profile(id: ProfileID("dev.follower.ada")), ada.id != host.id {
            items.append(
                RoomMemberItem(
                    profile: ada,
                    role: .admin,
                    joinedAt: room.createdAt.addingTimeInterval(86_400),
                    isOnline: true
                )
            )
        }
        if viewerID != host.id {
            items.append(
                RoomMemberItem(
                    profile: DemoExploreIdentity.profile(),
                    role: .member,
                    joinedAt: .now.addingTimeInterval(-604_800),
                    isOnline: false
                )
            )
        }
        return items
    }
}
