import Foundation
import Observation

@Observable
@MainActor
final class TradeRoomsHomeViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var viewerID: ProfileID?
    var searchText = ""

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let navigationHost: TradeRoomNavigationHost
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?

    private var ownerProfiles: [ProfileID: Profile] = [:]
    private var loadTask: Task<Void, Never>?
    private var roomUnreadTask: Task<Void, Never>?
    private var roomReadCursorTask: Task<Void, Never>?

    init(
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: TradeRoomNavigationHost = .messages,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
    }

    /// Always derived from the shared inbox store so mark-read / realtime patches refresh badges.
    var items: [TradeRoomInboxItem] {
        buildItems()
    }

    var filteredItems: [TradeRoomInboxItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.room.name.localizedCaseInsensitiveContains(query)
                || ($0.ownerName?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.preview.localizedCaseInsensitiveContains(query)
                || $0.room.slug.localizedCaseInsensitiveContains(query)
        }
    }

    var showsEmpty: Bool {
        phase == .loaded && items.isEmpty
    }

    var showsFilteredEmpty: Bool {
        phase == .loaded && !items.isEmpty && filteredItems.isEmpty
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded else { return }
        loadTask = Task { await performLoad(forceNetwork: false) }
    }

    func refresh() async {
        await performLoad(forceNetwork: true)
    }

    func openRoom(_ item: TradeRoomInboxItem) {
        ExperienceHaptics.play(.selection)
        inboxStore.markRoomRead(roomID: item.id)
        if let viewerID, !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            Task {
                try? await rooms.markRead(roomID: item.id)
                inboxStore.markRoomRead(roomID: item.id)
            }
        }
        navigationCoordinator.open(navigationHost.room(item.id))
    }

    func toggleMute(roomID: RoomID) {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(roomID: roomID)
    }

    func leaveRoom(id: RoomID) async {
        ExperienceHaptics.play(.warning)
        guard let viewerID else {
            inboxStore.removeRoom(id: id)
            return
        }
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || id.rawValue.hasPrefix("dev-") {
            inboxStore.removeRoom(id: id)
            return
        }
        do {
            try await rooms.leave(roomID: id, profileID: viewerID)
            inboxStore.removeRoom(id: id)
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    private func performLoad(forceNetwork: Bool) async {
        if !forceNetwork, inboxStore.hasLoaded, !inboxStore.rooms.isEmpty {
            viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
            await hydrateOwners(for: inboxStore.rooms)
            phase = .loaded
            await registerRealtime()
            loadTask = nil
            return
        }

        phase = phase == .loaded ? .loaded : .loading
        do {
            let current = await session.currentUserID
            let viewer = current.map { ProfileID($0.rawValue) }
            viewerID = viewer

            if let viewer, MessagesInboxSupport.isLocalDevelopmentProfile(viewer) {
                TradeRoomsFixtures.seedInbox(inboxStore, viewerID: viewer)
                await hydrateOwners(for: inboxStore.rooms)
                phase = .loaded
                await registerRealtime()
                loadTask = nil
                return
            }

            guard let viewer else {
                phase = .loaded
                loadTask = nil
                return
            }

            let memberRooms = try await rooms.memberRooms(
                for: viewer,
                page: PageRequest(limit: 50)
            ).items
            let unread = (try? await rooms.unreadCounts(for: memberRooms.map(\.id))) ?? [:]
            inboxStore.replaceRooms(memberRooms, unread: unread)
            await hydrateOwners(for: memberRooms)
            phase = .loaded
            await registerRealtime()
        } catch {
            if !inboxStore.rooms.isEmpty {
                phase = .loaded
            } else {
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func buildItems() -> [TradeRoomInboxItem] {
        inboxStore.rooms.map { room in
            let owner = ownerProfiles[room.ownerProfileID] ?? detailCache.profile(id: room.ownerProfileID)
            return TradeRoomInboxItem(
                room: room,
                ownerName: owner?.displayName,
                ownerIsVerified: owner?.isCreator == true,
                preview: inboxStore.roomPreviews[room.id] ?? room.description ?? "No messages yet",
                timestamp: room.createdAt,
                unreadCount: inboxStore.roomUnread[room.id] ?? 0,
                isMuted: inboxStore.isRoomMuted(room.id)
            )
        }
        .sorted { lhs, rhs in
            let lu = lhs.unreadCount > 0
            let ru = rhs.unreadCount > 0
            if lu != ru { return lu && !ru }
            return lhs.room.name.localizedCaseInsensitiveCompare(rhs.room.name) == .orderedAscending
        }
    }

    private func hydrateOwners(for rooms: [TradeRoom]) async {
        for room in rooms {
            let ownerID = room.ownerProfileID
            if let cached = detailCache.profile(id: ownerID) {
                ownerProfiles[ownerID] = cached
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
                ownerProfiles[ownerID] = fixture
                continue
            }
            if let profile = try? await profiles.profile(id: ownerID) {
                detailCache.seed(profile)
                ownerProfiles[ownerID] = profile
            }
        }
    }

    private func registerRealtime() async {
        guard let realtimeHub else { return }
        let channel = RealtimeChannelID(kind: .room, topic: "trade-rooms-home")
        try? await realtimeHub.subscriptions.subscribe(channel)
        await startRoomUnreadRealtimeIfNeeded()
        await startRoomReadCursorRealtimeIfNeeded()
    }

    /// Inbound `room_messages` for member rooms — bump unread when that room is not open.
    private func startRoomUnreadRealtimeIfNeeded() async {
        guard let realtimeHub,
              let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
        else { return }
        guard roomUnreadTask == nil else { return }
        let roomIDs = inboxStore.rooms.map(\.id.rawValue)
        guard !roomIDs.isEmpty else { return }

        roomUnreadTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchMemberRoomMessages(
                roomIDs: roomIDs,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard signal.kind == .insert else { continue }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                guard inboxStore.activeRoomID != roomID else { continue }
                inboxStore.markRoomUnread(roomID: roomID)
            }
            roomUnreadTask = nil
        }
    }

    /// Another device advances `room_members.last_read_*` — patch that room only.
    private func startRoomReadCursorRealtimeIfNeeded() async {
        guard let realtimeHub,
              let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
        else { return }
        guard roomReadCursorTask == nil else { return }

        roomReadCursorTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchRoomReadCursors(
                userID: viewerID.rawValue,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                let locallyCleared = (inboxStore.roomUnread[roomID] ?? 0) == 0
                if let counts = try? await rooms.unreadCounts(for: [roomID]),
                   let count = counts[roomID]
                {
                    inboxStore.setRoomUnread(roomID: roomID, count: locallyCleared ? 0 : count)
                } else if locallyCleared {
                    inboxStore.markRoomRead(roomID: roomID)
                }
            }
            roomReadCursorTask = nil
        }
    }
}
