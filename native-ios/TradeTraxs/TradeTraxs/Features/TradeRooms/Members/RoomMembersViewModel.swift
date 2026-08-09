import Foundation
import Observation

@Observable
@MainActor
final class RoomMembersViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let roomID: RoomID

    private(set) var phase: Phase = .idle
    private(set) var room: TradeRoom?
    private(set) var members: [RoomMemberItem] = []
    private(set) var viewerID: ProfileID?
    var searchText = ""

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

    var filteredMembers: [RoomMemberItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return members }
        return members.filter {
            $0.profile.displayName.localizedCaseInsensitiveContains(query)
                || $0.profile.username.localizedCaseInsensitiveContains(query)
                || $0.role.rawValue.localizedCaseInsensitiveContains(query)
        }
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

    func openProfile(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.profile(profileID))
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
                members = TradeRoomsFixtures.members(
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
                phase = .loaded
                loadTask = nil
                return
            }

            let loaded = try await rooms.room(id: roomID)
            room = loaded

            var assembled: [RoomMemberItem] = []
            let ownerProfile = try await resolveProfile(loaded.ownerProfileID)
            if let ownerProfile {
                assembled.append(
                    RoomMemberItem(
                        profile: ownerProfile,
                        role: .owner,
                        joinedAt: loaded.createdAt,
                        isOnline: false
                    )
                )
            }

            if let viewer,
               let membership = try? await rooms.membership(roomID: roomID, profileID: viewer),
               viewer != loaded.ownerProfileID,
               let viewerProfile = try await resolveProfile(viewer)
            {
                assembled.append(
                    RoomMemberItem(
                        profile: viewerProfile,
                        role: membership.role,
                        joinedAt: membership.joinedAt,
                        isOnline: true
                    )
                )
            }

            // Active participants from recent room messages (no members list API on RoomRepository).
            let page = try await rooms.messages(roomID: roomID, page: PageRequest(limit: 80))
            var seen = Set(assembled.map(\.id))
            for message in page.items {
                let senderID = message.senderProfileID
                guard !seen.contains(senderID) else { continue }
                seen.insert(senderID)
                guard let profile = try await resolveProfile(senderID) else { continue }
                let role: RoomMemberRole = senderID == loaded.ownerProfileID ? .owner : .member
                assembled.append(
                    RoomMemberItem(
                        profile: profile,
                        role: role,
                        joinedAt: nil,
                        isOnline: false
                    )
                )
            }

            members = assembled.sorted { lhs, rhs in
                roleRank(lhs.role) < roleRank(rhs.role)
                    || (lhs.role == rhs.role
                        && lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
                            == .orderedAscending)
            }
            phase = .loaded
        } catch {
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
        loadTask = nil
    }

    private func resolveProfile(_ id: ProfileID) async throws -> Profile? {
        if let cached = detailCache.profile(id: id) { return cached }
        if id.rawValue.hasPrefix("dev."), let fixture = FollowListFixtures.profile(id: id) {
            detailCache.seed(fixture)
            return fixture
        }
        let profile = try await profiles.profile(id: id)
        detailCache.seed(profile)
        return profile
    }

    private func roleRank(_ role: RoomMemberRole) -> Int {
        switch role {
        case .owner: return 0
        case .admin: return 1
        case .member: return 2
        }
    }
}
