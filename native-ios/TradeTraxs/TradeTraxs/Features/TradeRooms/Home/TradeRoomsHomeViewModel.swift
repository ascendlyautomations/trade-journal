import Foundation
import Observation

/// Trade Rooms home screen owner — presentation over ``MessagingDomain``.
///
/// Initial member-rooms network / room realtime ownership lives in the shared messaging domain
/// (same bootstrap as Messages home).
@Observable
@MainActor
final class TradeRoomsHomeViewModel {
    typealias Phase = MessagingState.Phase

    private(set) var phase: Phase = .idle
    private(set) var viewerID: ProfileID?
    var searchText = ""

    private let messages: any MessageRepository
    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let navigationHost: TradeRoomNavigationHost
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?
    private let domain: MessagingDomain

    private var loadTask: Task<Void, Never>?

    init(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        navigationHost: TradeRoomNavigationHost = .messages,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil,
        domain: MessagingDomain? = nil
    ) {
        self.messages = messages
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
        self.domain = domain ?? .shared
        self.domain.configure(
            messages: messages,
            rooms: rooms,
            profiles: profiles,
            session: session,
            detailCache: detailCache,
            realtimeHub: realtimeHub
        )
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
        // Mark-read runs inside ``NavigationCoordinator`` for `.messages(.room)`.
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
        if phase != .loaded {
            phase = .loading
        }
        if forceNetwork {
            await domain.refreshRooms()
        } else {
            await domain.bootstrapRoomsIfNeeded(forceNetwork: false)
        }
        viewerID = domain.state.viewerID
        phase = domain.state.phase
        await domain.retainRealtime()
        loadTask = nil
    }

    private func buildItems() -> [TradeRoomInboxItem] {
        inboxStore.rooms.map { room in
            let owner = domain.profile(id: room.ownerProfileID) ?? detailCache.profile(id: room.ownerProfileID)
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
}

/// Canonical screen name for Trade Rooms home.
typealias TradeRoomsScreenViewModel = TradeRoomsHomeViewModel

/// Room conversation thread — pagination / composer remain thread-scoped.
typealias RoomConversationScreenViewModel = RoomConversationViewModel
