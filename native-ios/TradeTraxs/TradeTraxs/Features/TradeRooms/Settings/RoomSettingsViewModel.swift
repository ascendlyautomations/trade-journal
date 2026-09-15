import Foundation
import Observation

@Observable
@MainActor
final class RoomSettingsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let roomID: RoomID

    private(set) var phase: Phase = .idle
    private(set) var room: TradeRoom?
    private(set) var viewerID: ProfileID?
    var showsLeaveConfirmation = false
    var showsDeleteConfirmation = false
    var isLeaving = false
    var isDeleting = false
    var statusMessage: String?

    private let rooms: any RoomRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost
    private let inboxStore: MessagesInboxStore

    private var loadTask: Task<Void, Never>?

    init(
        roomID: RoomID,
        rooms: any RoomRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.inboxStore = inboxStore ?? .shared
    }

    var isOwner: Bool {
        guard let viewerID, let room else { return false }
        return room.ownerProfileID == viewerID
    }

    var canDeleteRoom: Bool {
        isOwner && room?.roomKind != .official
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded else { return }
        loadTask = Task { await performLoad() }
    }

    func retry() {
        guard loadTask == nil else { return }
        phase = .idle
        loadTask = Task { await performLoad() }
    }

    func leaveRoom() async {
        guard !isOwner, let viewerID else { return }
        isLeaving = true
        defer { isLeaving = false }
        ExperienceHaptics.play(.warning)
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            finalizeRoomExit()
            return
        }
        do {
            try await rooms.leave(roomID: roomID, profileID: viewerID)
            finalizeRoomExit()
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func deleteRoom() async {
        guard canDeleteRoom, let management = rooms as? any RoomManagementRepository else { return }
        isDeleting = true
        defer { isDeleting = false }
        ExperienceHaptics.play(.warning)
        if let viewerID,
           MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-")
        {
            finalizeRoomExit(clearOwnedCache: true)
            return
        }
        do {
            try await management.deleteRoom(roomID: roomID)
            finalizeRoomExit(clearOwnedCache: true)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    private func finalizeRoomExit(clearOwnedCache: Bool = false) {
        inboxStore.setActiveRoom(nil)
        inboxStore.removeRoom(id: roomID)
        if let viewerID {
            SocialPersistedCacheCoordinator.invalidateRoomSnapshot(viewerID: viewerID, roomID: roomID)
            SessionTradeRoomsDiscoveryStore.shared.invalidate(viewerID: viewerID)
            if clearOwnedCache {
                detailCache.seedOwnedTradeRoom(nil, for: viewerID)
            }
        }
        ExperienceHaptics.play(.success)
        navigationCoordinator?.open(.popToRoot(tabIdentifier))
    }

    private var tabIdentifier: TabIdentifier {
        switch navigationHost {
        case .home: return .home
        case .messages: return .messages
        case .feed: return .feed
        case .profile: return .profile
        }
    }

    private func performLoad() async {
        phase = .loading
        viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        do {
            if let viewerID,
               MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-")
            {
                room = TradeRoomsFixtures.room(id: roomID, ownerID: viewerID)
                    ?? inboxStore.rooms.first { $0.id == roomID }
                phase = .loaded
                loadTask = nil
                return
            }
            room = try await rooms.room(id: roomID)
            phase = .loaded
        } catch {
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
        loadTask = nil
    }
}
