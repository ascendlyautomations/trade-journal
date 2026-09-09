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
    var pendingMemberAction: ManageRoomViewModel.MemberAction?
    var showsMemberActionConfirmation = false
    var statusMessage: String?

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost
    private let inboxStore: MessagesInboxStore
    private let tagStore: SessionRoomMemberTagsStore

    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var initialLoadStarted = false

    init(
        roomID: RoomID,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        inboxStore: MessagesInboxStore? = nil,
        tagStore: SessionRoomMemberTagsStore? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.inboxStore = inboxStore ?? .shared
        self.tagStore = tagStore ?? .shared
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

    var isOwner: Bool {
        guard let viewerID, let room else { return false }
        return room.ownerProfileID == viewerID
    }

    var canManageRoom: Bool {
        guard let room else { return false }
        return TradeRoomManagementPermission.canManage(room: room, viewerID: viewerID)
    }

    func requestMemberAction(_ action: ManageRoomViewModel.MemberAction) {
        pendingMemberAction = action
        showsMemberActionConfirmation = true
    }

    func confirmMemberAction() async {
        guard canManageRoom,
              let management = rooms as? any RoomManagementRepository,
              let viewerID,
              let room,
              let action = pendingMemberAction
        else { return }
        let targetID: ProfileID
        switch action {
        case .remove(let profileID), .ban(let profileID):
            targetID = profileID
        }
        guard targetID != viewerID, targetID != room.ownerProfileID else { return }
        pendingMemberAction = nil
        showsMemberActionConfirmation = false
        do {
            switch action {
            case .remove(let profileID):
                try await management.removeMember(roomID: roomID, profileID: profileID)
                statusMessage = "Member removed."
            case .ban(let profileID):
                try await management.banMember(
                    roomID: roomID,
                    profileID: profileID,
                    bannedBy: viewerID
                )
                statusMessage = "Member banned."
            }
            members.removeAll { $0.id == targetID }
            let activeCount = (try? await rooms.activeMemberCounts(for: [roomID]))?[roomID] ?? members.count
            if var updated = self.room {
                updated.memberCount = activeCount
                self.room = updated
            }
            RoomMemberCountSync.apply(
                roomID: roomID,
                count: activeCount,
                inboxStore: inboxStore,
                viewerID: viewerID
            )
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func openManageRoom() {
        guard canManageRoom else { return }
        navigationCoordinator?.open(navigationHost.manageRoom(roomID))
    }

    func canManageMember(_ item: RoomMemberItem) -> Bool {
        guard canManageRoom, let viewerID, let room else { return false }
        return item.role != .owner
            && item.id != viewerID
            && item.id != room.ownerProfileID
    }

    func memberActionTitle(for action: ManageRoomViewModel.MemberAction) -> String {
        switch action {
        case .remove: return "Remove this member from the room?"
        case .ban: return "Ban this member from the room?"
        }
    }

    func memberActionButtonTitle(for action: ManageRoomViewModel.MemberAction) -> String {
        switch action {
        case .remove: return "Remove Member"
        case .ban: return "Ban Member"
        }
    }

    func loadIfNeeded() {
        guard !initialLoadStarted, loadTask == nil, phase != .loaded else { return }
        initialLoadStarted = true
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask = Task { await performLoad(generation: generation) }
    }

    func retry() {
        guard loadTask == nil else { return }
        loadGeneration &+= 1
        initialLoadStarted = true
        phase = .idle
        let generation = loadGeneration
        loadTask = Task { await performLoad(generation: generation) }
    }

    func openProfile(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.profile(profileID))
    }

    private func performLoad(generation: UInt64) async {
        RoomMembersLoadProbe.loadStarted(roomID: roomID)
        phase = .loading
        defer { loadTask = nil }

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
                RoomMembersLoadProbe.uiVisibleCount(members.count)
                return
            }

            let loaded = try await rooms.room(id: roomID)
            guard generation == loadGeneration else { return }
            room = loaded

            let activeRows = try await rooms.activeMembers(
                roomID: roomID,
                ownerProfileID: loaded.ownerProfileID
            )
            guard generation == loadGeneration else { return }
            RoomMembersLoadProbe.decoded(count: activeRows.count)

            let profileIDs = activeRows.map(\.profile.id)
            let missingProfileIDs = profileIDs.filter { id in
                resolveProfile(id) == nil
                    || activeRows.first(where: { $0.profile.id == id })?.profile.displayName == "Unknown User"
            }
            RoomMembersLoadProbe.profilesRequested(count: missingProfileIDs.count)

            let fetchedProfiles: [Profile]
            if missingProfileIDs.isEmpty {
                fetchedProfiles = []
            } else {
                fetchedProfiles = (try? await SessionProfileStore.shared.profiles(
                    ids: missingProfileIDs,
                    detailCache: detailCache,
                    repository: profiles
                )) ?? []
            }
            RoomMembersLoadProbe.profilesReturned(count: fetchedProfiles.count)

            let profileByID = Dictionary(
                uniqueKeysWithValues: (fetchedProfiles + activeRows.map(\.profile)).map { ($0.id, $0) }
            )

            members = activeRows.map { row in
                RoomMemberItem(
                    profile: profileByID[row.profile.id] ?? resolveProfile(row.profile.id) ?? row.profile,
                    role: row.role,
                    joinedAt: row.joinedAt,
                    isOnline: false,
                    tags: row.tags
                )
            }
            .sorted { lhs, rhs in
                roleRank(lhs.role) < roleRank(rhs.role)
                    || (lhs.role == rhs.role
                        && lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
                            == .orderedAscending)
            }

            let listCount = members.count
            let activeCount = (try? await rooms.activeMemberCounts(for: [roomID]))?[roomID] ?? listCount
            guard generation == loadGeneration else { return }

            room?.memberCount = activeCount
            RoomMemberCountSync.apply(
                roomID: roomID,
                count: activeCount,
                inboxStore: inboxStore,
                viewerID: viewer
            )
            RoomMemberCountProbe.record(
                roomID: roomID,
                displayedMemberCount: activeCount,
                activeMembershipCount: activeCount,
                loadedMemberListCount: listCount,
                source: .network
            )
            phase = .loaded
            RoomMembersLoadProbe.uiVisibleCount(listCount)

            await enrichMemberTagsIfNeeded(
                generation: generation,
                room: loaded,
                viewerID: viewer
            )
        } catch {
            guard generation == loadGeneration else { return }
            RoomMembersLoadProbe.failed(
                stage: failureStage(for: error),
                operation: failureOperation(for: error),
                error: error
            )
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
    }

    private func enrichMemberTagsIfNeeded(
        generation: UInt64,
        room: TradeRoom,
        viewerID: ProfileID?
    ) async {
        guard generation == loadGeneration else { return }
        guard let management = rooms as? any RoomManagementRepository else { return }

        let isOwner = viewerID == room.ownerProfileID
        let ensureStatus = await tagStore.ensureDefaultTagsIfOwner(
            roomID: roomID,
            isOwner: isOwner,
            repository: management
        )
        RoomMembersLoadProbe.ensureDefaults(status: ensureStatus)

        do {
            try await tagStore.hydrateTags(roomID: roomID, repository: management)
            guard generation == loadGeneration else { return }
            RoomMembersLoadProbe.tags(count: tagStore.tags(for: roomID).count)
            RoomMembersLoadProbe.assignments(count: tagStore.assignments(for: roomID).count)
            applyCachedTagsToMembers()
        } catch {
            RoomMembersLoadProbe.tagEnrichmentFailed(
                operation: "SessionRoomMemberTagsStore.hydrateTags",
                error: error
            )
        }
    }

    private func applyCachedTagsToMembers() {
        members = members.map { item in
            var updated = item
            updated.tags = tagStore.tags(for: item.id, roomID: roomID)
            return updated
        }
    }

    private func failureStage(for error: Error) -> RoomMembersLoadProbe.Stage {
        let description = String(describing: error).lowercased()
        if description.contains("room_members") || description.contains("decode") {
            return .memberships
        }
        if description.contains("profile") {
            return .profiles
        }
        if description.contains("ensure_room_member_tags") || description.contains("ensuredefault") {
            return .ensureDefaults
        }
        if description.contains("room_member_tags") {
            return .tags
        }
        if description.contains("room_member_tag_assignments") {
            return .assignments
        }
        return .room
    }

    private func failureOperation(for error: Error) -> String {
        let description = String(describing: error).lowercased()
        if description.contains("room_members") {
            return "DefaultRoomRepository.fetchActiveMemberRows"
        }
        if description.contains("profiles") {
            return "SessionProfileStore.profiles.batch"
        }
        if description.contains("room_member_tag_assignments") {
            return "DefaultRoomRepository.memberTagAssignments"
        }
        if description.contains("room_member_tags") {
            return "DefaultRoomRepository.memberTags"
        }
        return "DefaultRoomRepository.room"
    }

    private func resolveProfile(_ id: ProfileID) -> Profile? {
        if let cached = detailCache.profile(id: id) { return cached }
        if id.rawValue.hasPrefix("dev."), let fixture = FollowListFixtures.profile(id: id) {
            detailCache.seed(fixture)
            return fixture
        }
        return nil
    }

    private func roleRank(_ role: RoomMemberRole) -> Int {
        switch role {
        case .owner: return 0
        case .admin: return 1
        case .member: return 2
        }
    }
}
