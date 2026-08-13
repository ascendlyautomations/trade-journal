import Foundation

/// Coordinated messaging first-paint load — owned exclusively by ``MessagingDomain``.
///
/// Conversations + member rooms run concurrently. Results are written into
/// ``MessagesInboxStore`` (presentation cache) and session stores (network coalescing).
/// Conforms to ``ScreenBootstrap`` via ``load`` → ``loadHome``.
@MainActor
enum MessagingBootstrap: ScreenBootstrap {
    struct Context {
        var messages: any MessageRepository
        var rooms: any RoomRepository
        var profiles: any ProfileRepository
        var session: any SessionProviding
        var detailCache: DetailPresentationCache
        var inboxStore: MessagesInboxStore
        var forceNetwork: Bool
    }

    struct Result {
        var viewerID: ProfileID?
        var peerProfiles: [ProfileID: Profile]
        var usedDevelopmentFixtures: Bool
        var loadedConversations: Bool
        var loadedRooms: Bool
    }

    /// ``ScreenBootstrap`` entry — same as ``loadHome``.
    static func load(_ context: Context) async throws -> Result {
        try await loadHome(context)
    }

    /// Full Messages home bootstrap — conversations ∥ member rooms + peer/owner hydrate.
    static func loadHome(_ context: Context) async throws -> Result {
        let viewer = await context.session.currentUserID.map { ProfileID($0.rawValue) }

        if let viewer, MessagesInboxSupport.isLocalDevelopmentProfile(viewer) {
            MessagesInboxFixtures.seedStore(context.inboxStore, viewerID: viewer)
            let peers = MessagesInboxFixtures.profiles(
                for: context.inboxStore.conversations,
                viewerID: viewer
            )
            for profile in peers {
                context.detailCache.seed(profile)
            }
            await hydrateOwners(
                for: context.inboxStore.rooms,
                profiles: context.profiles,
                detailCache: context.detailCache
            )
            return Result(
                viewerID: viewer,
                peerProfiles: Dictionary(uniqueKeysWithValues: peers.map { ($0.id, $0) }),
                usedDevelopmentFixtures: true,
                loadedConversations: true,
                loadedRooms: true
            )
        }

        guard let viewer else {
            return Result(
                viewerID: nil,
                peerProfiles: [:],
                usedDevelopmentFixtures: false,
                loadedConversations: true,
                loadedRooms: true
            )
        }

        async let conversationsTask = context.messages.conversations(page: PageRequest(limit: 100))
        async let roomsTask = SessionMemberRoomsStore.shared.memberRooms(
            for: viewer,
            repository: context.rooms,
            forceNetwork: context.forceNetwork
        )

        let conversationResult = try await conversationsTask
        let (memberRooms, roomUnread) = try await roomsTask

        context.inboxStore.replaceConversations(conversationResult.items)
        context.inboxStore.replaceRooms(memberRooms, unread: roomUnread)

        SessionProfileStore.shared.seed(
            conversationResult.embeddedProfiles,
            detailCache: context.detailCache
        )

        var peers = Dictionary(
            uniqueKeysWithValues: conversationResult.embeddedProfiles.map { ($0.id, $0) }
        )
        let resolved = await resolvePeers(
            conversations: conversationResult.items,
            rooms: memberRooms,
            viewerID: viewer,
            profiles: context.profiles,
            detailCache: context.detailCache
        )
        for profile in resolved {
            peers[profile.id] = profile
        }

        return Result(
            viewerID: viewer,
            peerProfiles: peers,
            usedDevelopmentFixtures: false,
            loadedConversations: true,
            loadedRooms: true
        )
    }

    /// Trade Rooms–only path when the full inbox has not been bootstrapped yet.
    static func loadRoomsOnly(_ context: Context) async throws -> Result {
        let viewer = await context.session.currentUserID.map { ProfileID($0.rawValue) }

        if let viewer, MessagesInboxSupport.isLocalDevelopmentProfile(viewer) {
            TradeRoomsFixtures.seedInbox(context.inboxStore, viewerID: viewer)
            await hydrateOwners(
                for: context.inboxStore.rooms,
                profiles: context.profiles,
                detailCache: context.detailCache
            )
            return Result(
                viewerID: viewer,
                peerProfiles: [:],
                usedDevelopmentFixtures: true,
                loadedConversations: context.inboxStore.hasLoaded,
                loadedRooms: true
            )
        }

        guard let viewer else {
            return Result(
                viewerID: nil,
                peerProfiles: [:],
                usedDevelopmentFixtures: false,
                loadedConversations: context.inboxStore.hasLoaded,
                loadedRooms: true
            )
        }

        let (memberRooms, unread) = try await SessionMemberRoomsStore.shared.memberRooms(
            for: viewer,
            repository: context.rooms,
            forceNetwork: context.forceNetwork
        )
        context.inboxStore.replaceRooms(memberRooms, unread: unread)
        let owners = await hydrateOwners(
            for: memberRooms,
            profiles: context.profiles,
            detailCache: context.detailCache
        )

        return Result(
            viewerID: viewer,
            peerProfiles: owners,
            usedDevelopmentFixtures: false,
            loadedConversations: context.inboxStore.hasLoaded,
            loadedRooms: true
        )
    }

    // MARK: - Hydration

    private static func resolvePeers(
        conversations: [Conversation],
        rooms: [TradeRoom],
        viewerID: ProfileID,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache
    ) async -> [Profile] {
        let peerIDs = conversations.compactMap {
            MessagesInboxSupport.peerID(in: $0, viewerID: viewerID)
        }
        let ownerIDs = rooms.map(\.ownerProfileID)
        let needed = Array(Set(peerIDs + ownerIDs))
        guard !needed.isEmpty else { return [] }
        return (try? await SessionProfileStore.shared.profiles(
            ids: needed,
            detailCache: detailCache,
            repository: profiles
        )) ?? []
    }

    @discardableResult
    private static func hydrateOwners(
        for rooms: [TradeRoom],
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache
    ) async -> [ProfileID: Profile] {
        var result: [ProfileID: Profile] = [:]
        var missing: [ProfileID] = []
        for room in rooms {
            let ownerID = room.ownerProfileID
            if let cached = detailCache.profile(id: ownerID) {
                result[ownerID] = cached
                continue
            }
            if MessagesInboxSupport.isLocalDevelopmentProfile(ownerID)
                || ownerID.rawValue.hasPrefix("dev.")
            {
                let fixture = FollowListFixtures.profile(id: ownerID)
                    ?? Profile(
                        id: ownerID,
                        userID: UserID(ownerID.rawValue),
                        username: "owner",
                        displayName: "Room Owner",
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
                detailCache.seed(fixture)
                result[ownerID] = fixture
                continue
            }
            missing.append(ownerID)
        }
        guard !missing.isEmpty else { return result }
        let fetched = (try? await SessionProfileStore.shared.profiles(
            ids: missing,
            detailCache: detailCache,
            repository: profiles
        )) ?? []
        for profile in fetched {
            result[profile.id] = profile
        }
        return result
    }
}
