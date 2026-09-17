import Foundation
import Observation
import UIKit

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
    var statusMessage: String?
    var isSavingDetails = false

    // Owner editing
    var editName = ""
    var editDescription = ""
    var editShowsOnProfile = true
    var pendingImageData: Data?
    var pendingImagePreview: UIImage?

    private let rooms: any RoomRepository
    private let uploadService: any UploadService
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
        uploadService: any UploadService,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.uploadService = uploadService
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

    var displayedMemberCount: Int? {
        inboxStore.rooms.first(where: { $0.id == roomID })?.memberCount ?? room?.memberCount
    }

    var isOwner: Bool {
        guard let viewerID, let room else { return false }
        return room.ownerProfileID == viewerID
    }

    var isMember: Bool {
        membership != nil
    }

    var canManageRoom: Bool {
        guard let room else { return false }
        return TradeRoomManagementPermission.canManage(room: room, viewerID: viewerID)
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

    func openManageRoom() {
        guard canManageRoom else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.manageRoom(roomID))
    }

    func setCroppedRoomImage(_ result: ImageCropSelectionResult) {
        guard let applied = ComposerCropImageState.apply(result) else { return }
        pendingImagePreview = applied.finalImage
        pendingImageData = applied.uploadData
    }

    func saveDetails() async {
        guard canManageRoom, let management = rooms as? any RoomManagementRepository else { return }
        isSavingDetails = true
        defer { isSavingDetails = false }
        do {
            var imageURL: String?
            if let imageData = pendingImageData {
                let path = "room-images/\(Int(Date().timeIntervalSince1970))-avatar.jpg"
                let reference = try await uploadService.upload(
                    UploadRequest(
                        bucket: "avatars",
                        path: path,
                        data: imageData,
                        contentType: "image/jpeg",
                        purpose: .profileAvatar
                    )
                )
                imageURL = reference.id
                pendingImageData = nil
                pendingImagePreview = nil
            }
            let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let baseRoom = room else { return }
            let channels = (try? await rooms.channels(roomID: roomID)) ?? []
            var configuration = TradeRoomConfiguration(room: baseRoom, channels: channels)
            if !trimmedName.isEmpty {
                configuration.name = trimmedName
            }
            configuration.description = trimmedDescription.isEmpty ? nil : trimmedDescription
            configuration.showsOnProfile = editShowsOnProfile
            if let imageURL {
                configuration.imageURL = imageURL
            }
            let updated = try await management.updateRoom(
                roomID: roomID,
                request: RoomUpdateRequest(configuration: configuration)
            )
            room = updated
            RoomMetadataSync.apply(
                updated,
                inboxStore: inboxStore,
                detailCache: detailCache,
                viewerID: viewerID
            )
            statusMessage = "Room details saved."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func openMembers() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.members(roomID))
    }

    func openRoomSettings() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.roomSettings(roomID))
    }

    func leaveRoom() async {
        guard let viewerID else { return }
        ExperienceHaptics.play(.warning)
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            inboxStore.removeRoom(id: roomID)
            didLeave = true
            ExperienceHaptics.play(.success)
            navigationCoordinator?.pop()
            navigationCoordinator?.pop()
            return
        }
        do {
            try await rooms.leave(roomID: roomID, profileID: viewerID)
            inboxStore.removeRoom(id: roomID)
            didLeave = true
            ExperienceHaptics.play(.success)
            navigationCoordinator?.pop()
            navigationCoordinator?.pop()
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
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
            editName = loaded.name
            editDescription = loaded.description ?? ""
            editShowsOnProfile = loaded.showsOnProfile
            if let cached = detailCache.profile(id: loaded.ownerProfileID) {
                ownerProfile = cached
            } else if let owner = try? await SessionProfileStore.shared.profiles(
                ids: [loaded.ownerProfileID],
                detailCache: detailCache,
                repository: profiles
            ).first {
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
