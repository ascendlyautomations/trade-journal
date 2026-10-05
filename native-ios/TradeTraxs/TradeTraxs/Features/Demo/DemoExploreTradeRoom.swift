import Foundation

/// Local read-only Trade Room for Explore Mode — never synced to Supabase.
nonisolated enum DemoExploreTradeRoom {
    static let roomID = RoomID("demo.explore.trade-room")
    static let hostProfileID = ProfileID("demo.explore.community.host")

    static func isLocalRoom(_ id: RoomID) -> Bool { id == roomID }

    static func room(now: Date = Date()) -> TradeRoom {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.room
        }
        return bundledRoom(now: now)
    }

    private static func bundledRoom(now: Date = Date()) -> TradeRoom {
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
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.channels.filter { $0.roomID == roomID }
        }
        return bundledChannels(roomID: roomID)
    }

    private static func bundledChannels(roomID: RoomID) -> [RoomChannel] {
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
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.host
        }
        return bundledHostProfile()
    }

    private static func bundledHostProfile() -> Profile {
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
        if let snapshot = DemoSnapshotStore.shared.current {
            _ = viewerID
            return [snapshot.host, snapshot.viewer] + snapshot.peers
        }
        var profiles = [hostProfile(), DemoExploreIdentity.profile()]
        profiles.append(contentsOf: DemoGraph.profiles())
        _ = viewerID
        return profiles
    }

    static func messages(
        roomID: RoomID = roomID,
        viewerID: ProfileID,
        channelID: RoomChannelID? = nil,
        now: Date = Date()
    ) -> [RoomMessage] {
        if let snapshot = DemoSnapshotStore.shared.current {
            let stored = snapshot.roomMessages.filter { $0.roomID == roomID }
            guard let channelID else { return stored }
            let channel = channels(roomID: roomID).first { $0.id == channelID }
            if channel?.isGeneral == true {
                return stored.filter { $0.channelID == channelID || $0.channelID == nil }
            }
            return stored.filter { $0.channelID == channelID }
        }
        let channels = bundledChannels(roomID: roomID)
        let general = channels.first { $0.isGeneral }?.id
        let setups = channels.first { $0.name == "setups" }?.id
        let recap = channels.first { $0.name == "recap" }?.id
        let ada = DemoGraph.sarahID
        let sampleTradeID = DemoGraph.featuredTrade().id

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
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.memberships.compactMap { membership in
                guard let profile = profileForMembership(membership.profileID, viewerID: viewerID) else { return nil }
                return RoomMemberItem(
                    profile: profile,
                    role: membership.role,
                    joinedAt: membership.joinedAt,
                    isOnline: membership.role != .member || membership.profileID != viewerID
                )
            }
        }
        let room = bundledRoom()
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

    private static func profileForMembership(_ id: ProfileID, viewerID: ProfileID) -> Profile? {
        if id == DemoExperienceSupport.profileID || id == viewerID {
            return DemoCanonicalDataset.profile()
        }
        if id == hostProfileID {
            return hostProfile()
        }
        return DemoGraph.profile(id: id)
    }

    static func discoverySuggestion(joined: Bool) -> ExploreRoomSuggestion {
        let sample = room()
        return ExploreRoomSuggestion(
            id: sample.id,
            name: sample.name,
            slug: sample.slug,
            description: sample.description,
            memberCount: sample.memberCount,
            ownerProfileID: sample.ownerProfileID,
            roomKind: sample.roomKind,
            discoveryTags: sample.discoveryTags,
            isJoined: joined,
            isOwner: false,
            isMember: joined
        )
    }

    static func homeBootstrap(
        viewerID: ProfileID,
        scope: TradeRoomDiscoveryScope
    ) -> TradeRoomsHomeBootstrap {
        let sample = room()
        let yours = ExploreRoomSuggestion(
            id: sample.id,
            name: sample.name,
            slug: sample.slug,
            description: sample.description,
            memberCount: sample.memberCount,
            ownerProfileID: sample.ownerProfileID,
            roomKind: sample.roomKind,
            discoveryTags: sample.discoveryTags,
            isJoined: true,
            isOwner: false,
            isMember: true,
            joinPolicy: sample.joinPolicy
        )
        return TradeRoomsHomeBootstrap(
            viewerID: viewerID,
            scope: scope,
            yourRooms: [yours],
            suggested: [],
            popular: []
        )
    }
}
