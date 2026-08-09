import Foundation
import Observation

@Observable
@MainActor
final class RoomInfoViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let roomID: RoomID

    private(set) var phase: Phase = .idle
    private(set) var room: TradeRoom?
    private(set) var ownerProfile: Profile?
    private(set) var moderators: [Profile] = []
    private(set) var membership: RoomMembership?
    private(set) var viewerID: ProfileID?
    private(set) var didLeave = false
    var showsLeaveConfirmation = false
    var showsReportConfirmation = false
    var statusMessage: String?

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost
    private let inboxStore: MessagesInboxStore

    private var loadTask: Task<Void, Never>?

    init(
        roomID: RoomID,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.inboxStore = inboxStore ?? .shared
    }

    var inviteLink: String {
        let slug = room?.slug ?? roomID.rawValue
        return "https://www.tradetraxs.com/rooms/\(slug)"
    }

    var rulesText: String {
        """
        Be respectful. No spam, no financial advice guarantees, and keep screenshots \
        of your own journal. Moderators may remove messages that break community standards.
        """
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

    func openOwner() {
        guard let ownerProfile else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.profile(ownerProfile.id))
    }

    func openMembers() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.members(roomID))
    }

    func leaveRoom() async {
        guard let viewerID else { return }
        ExperienceHaptics.play(.warning)
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            inboxStore.removeRoom(id: roomID)
            didLeave = true
            navigationCoordinator?.pop()
            navigationCoordinator?.pop()
            return
        }
        do {
            try await rooms.leave(roomID: roomID, profileID: viewerID)
            inboxStore.removeRoom(id: roomID)
            didLeave = true
            navigationCoordinator?.pop()
            navigationCoordinator?.pop()
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func reportRoom() {
        ExperienceHaptics.play(.warning)
        statusMessage = "Thanks — this room was reported for review."
    }

    private func performLoad() async {
        phase = .loading
        let viewer = await session.currentUserID.map { ProfileID($0.rawValue) }
        viewerID = viewer

        do {
            if let viewer,
               MessagesInboxSupport.isLocalDevelopmentProfile(viewer)
                || roomID.rawValue.hasPrefix("dev-")
            {
                let fixture = TradeRoomsFixtures.room(id: roomID, ownerID: viewer)
                    ?? inboxStore.rooms.first { $0.id == roomID }
                room = fixture
                ownerProfile = FollowListFixtures.profile(id: fixture?.ownerProfileID ?? viewer)
                    ?? FollowListFixtures.profile(id: viewer)
                if let ownerProfile { detailCache.seed(ownerProfile) }
                moderators = TradeRoomsFixtures.members(
                    room: fixture ?? TradeRoom(
                        id: roomID,
                        ownerProfileID: viewer,
                        name: "Trade Room",
                        slug: roomID.rawValue,
                        description: nil,
                        image: nil,
                        memberCount: 0,
                        showsOnProfile: true,
                        createdAt: .now
                    ),
                    viewerID: viewer
                )
                .filter { $0.role == .admin || $0.role == .owner }
                .map(\.profile)
                membership = RoomMembership(
                    roomID: roomID,
                    profileID: viewer,
                    role: fixture?.ownerProfileID == viewer ? .owner : .member,
                    joinedAt: fixture?.createdAt ?? .now,
                    notificationsEnabled: !inboxStore.isRoomMuted(roomID)
                )
                phase = .loaded
                loadTask = nil
                return
            }

            let loaded = try await rooms.room(id: roomID)
            room = loaded
            if let cached = detailCache.profile(id: loaded.ownerProfileID) {
                ownerProfile = cached
            } else if let owner = try? await profiles.profile(id: loaded.ownerProfileID) {
                detailCache.seed(owner)
                ownerProfile = owner
            }
            if let viewer {
                membership = try? await rooms.membership(roomID: roomID, profileID: viewer)
            }
            if let ownerProfile {
                moderators = [ownerProfile]
            }
            phase = .loaded
        } catch {
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
        loadTask = nil
    }
}
