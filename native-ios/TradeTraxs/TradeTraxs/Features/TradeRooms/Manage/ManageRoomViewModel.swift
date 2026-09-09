import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ManageRoomViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum MemberAction: Identifiable, Equatable {
        case remove(ProfileID)
        case ban(ProfileID)

        var id: String {
            switch self {
            case .remove(let id): return "remove-\(id.rawValue)"
            case .ban(let id): return "ban-\(id.rawValue)"
            }
        }
    }

    enum ChannelDeleteConfirmation: Identifiable, Equatable {
        case empty(RoomChannelID)
        case withMessages(RoomChannelID, messageCount: Int)

        var id: String {
            switch self {
            case .empty(let channelID): return "empty-\(channelID.rawValue)"
            case .withMessages(let channelID, _): return "messages-\(channelID.rawValue)"
            }
        }

        var channelID: RoomChannelID {
            switch self {
            case .empty(let id), .withMessages(let id, _): return id
            }
        }
    }

    let roomID: RoomID

    private(set) var phase: Phase = .idle
    private(set) var room: TradeRoom?
    private(set) var channels: [RoomChannel] = []
    private(set) var members: [RoomManagedMember] = []
    private(set) var tags: [RoomMemberTag] = []
    private(set) var bans: [RoomBanRecord] = []
    private(set) var joinRequests: [RoomJoinRequestRecord] = []
    private(set) var viewerID: ProfileID?
    var statusMessage: String?
    var pendingMemberAction: MemberAction?
    var pendingChannelDelete: ChannelDeleteConfirmation?
    var isSavingDetails = false
    var isMutatingMember = false
    var isMutatingTag = false
    var isMutatingChannel = false
    var isMutatingJoinRequest = false

    // Editable room details (shared model with create flow)
    var editConfiguration = TradeRoomConfiguration.defaultDraft(username: nil)
    var pendingImageData: Data?
    var pendingImagePreview: UIImage?
    /// Authoritative saved image from the current room model (not cleared while refreshing).
    private(set) var savedImageReference: MediaReference?
    /// User chose to remove the saved room image on next save.
    var marksImageForRemoval = false

    var hasDisplayImage: Bool {
        pendingImagePreview != nil
            || (savedImageReference != nil && !marksImageForRemoval)
    }

    func setCroppedRoomImage(_ result: ImageCropSelectionResult) {
        guard let applied = ComposerCropImageState.apply(result) else { return }
        pendingImagePreview = applied.finalImage
        pendingImageData = applied.uploadData
        marksImageForRemoval = false
    }

    func clearPendingRoomImage() {
        if pendingImagePreview != nil || pendingImageData != nil {
            pendingImagePreview = nil
            pendingImageData = nil
            marksImageForRemoval = false
            return
        }
        if savedImageReference != nil {
            marksImageForRemoval = true
        }
    }

    func applyRoomSnapshot(_ loaded: TradeRoom, channels: [RoomChannel]) {
        room = loaded
        editConfiguration = TradeRoomConfiguration(room: loaded, channels: channels)
        savedImageReference = loaded.image
    }

    private let rooms: any RoomManagementRepository
    private let uploadService: any UploadService
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let tagStore: SessionRoomMemberTagsStore
    private let inboxStore: MessagesInboxStore
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost

    private var loadTask: Task<Void, Never>?

    init(
        roomID: RoomID,
        rooms: any RoomManagementRepository,
        uploadService: any UploadService,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        tagStore: SessionRoomMemberTagsStore? = nil,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.uploadService = uploadService
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.tagStore = tagStore ?? .shared
        self.inboxStore = inboxStore ?? .shared
        hydrateFromCacheIfAvailable()
    }

    private func hydrateFromCacheIfAvailable() {
        guard room == nil, let cached = inboxStore.rooms.first(where: { $0.id == roomID }) else { return }
        applyRoomSnapshot(cached, channels: [])
    }

    var isOwner: Bool {
        guard let viewerID, let room else { return false }
        return room.ownerProfileID == viewerID
    }

    var canManageRoom: Bool {
        guard let room else { return false }
        return TradeRoomManagementPermission.canManage(room: room, viewerID: viewerID)
    }

    var showsJoinRequestsSection: Bool {
        guard canManageRoom, let room else { return false }
        return room.joinPolicy == .approval && !room.isPrivate
    }

    var pendingJoinRequestCount: Int {
        joinRequests.count
    }

    func refreshJoinRequests() async {
        guard showsJoinRequestsSection else {
            joinRequests = []
            return
        }
        do {
            joinRequests = try await rooms.pendingJoinRequests(roomID: roomID)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
        }
    }

    func approveJoinRequest(_ request: RoomJoinRequestRecord) async {
        guard canManageRoom else { return }
        isMutatingJoinRequest = true
        defer { isMutatingJoinRequest = false }
        do {
            try await rooms.resolveJoinRequest(requestID: request.id, action: .approve)
            joinRequests.removeAll { $0.id == request.id }
            await refreshMembersAndBans()
            statusMessage = "Join request approved."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func declineJoinRequest(_ request: RoomJoinRequestRecord) async {
        guard canManageRoom else { return }
        isMutatingJoinRequest = true
        defer { isMutatingJoinRequest = false }
        do {
            try await rooms.resolveJoinRequest(requestID: request.id, action: .decline)
            joinRequests.removeAll { $0.id == request.id }
            statusMessage = "Join request declined."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
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

    func refreshMembersAndBans() async {
        guard let room else { return }
        do {
            members = try await rooms.managedMembers(
                roomID: roomID,
                ownerProfileID: room.ownerProfileID
            )
            bans = try await rooms.bannedMembers(roomID: roomID)
            await syncAuthoritativeMemberCount(listCount: members.count)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
        }
    }

    private func syncAuthoritativeMemberCount(listCount: Int) async {
        let activeCount = (try? await rooms.activeMemberCounts(for: [roomID]))?[roomID] ?? listCount
        if var updated = room {
            updated.memberCount = activeCount
            room = updated
        }
        RoomMemberCountSync.apply(
            roomID: roomID,
            count: activeCount,
            inboxStore: inboxStore,
            viewerID: viewerID
        )
        RoomMemberCountProbe.record(
            roomID: roomID,
            displayedMemberCount: activeCount,
            activeMembershipCount: activeCount,
            loadedMemberListCount: listCount,
            source: .mutation
        )
    }

    func refreshTags() async {
        do {
            try await tagStore.hydrate(roomID: roomID, repository: rooms)
            tags = tagStore.tags(for: roomID)
            await refreshMembersAndBans()
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
        }
    }

    func saveDetails() async {
        guard canManageRoom else { return }
        isSavingDetails = true

        let rollbackConfiguration = editConfiguration
        let rollbackPendingPreview = pendingImagePreview
        let rollbackPendingData = pendingImageData
        let rollbackMarksRemoval = marksImageForRemoval
        let rollbackSavedReference = savedImageReference

        defer { isSavingDetails = false }
        do {
            var configuration = editConfiguration

            if marksImageForRemoval, pendingImageData == nil {
                configuration.imageURL = ""
            }

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
                configuration.imageURL = reference.id
            }

            let updated = try await rooms.updateRoom(
                roomID: roomID,
                request: RoomUpdateRequest(configuration: configuration)
            )
            applyRoomSnapshot(updated, channels: channels)
            pendingImageData = nil
            pendingImagePreview = nil
            marksImageForRemoval = false
            editConfiguration = TradeRoomConfiguration(room: updated, channels: channels)
            RoomMetadataSync.apply(
                updated,
                inboxStore: inboxStore,
                detailCache: detailCache,
                viewerID: viewerID
            )
            statusMessage = "Room details saved."
            ExperienceHaptics.play(.success)
        } catch {
            editConfiguration = rollbackConfiguration
            pendingImagePreview = rollbackPendingPreview
            pendingImageData = rollbackPendingData
            marksImageForRemoval = rollbackMarksRemoval
            savedImageReference = rollbackSavedReference
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func confirmMemberAction(_ action: MemberAction) async {
        guard canManageRoom, let viewerID, let room else { return }
        let targetID: ProfileID
        switch action {
        case .remove(let profileID), .ban(let profileID):
            targetID = profileID
        }
        guard targetID != viewerID, targetID != room.ownerProfileID else { return }
        isMutatingMember = true
        defer {
            isMutatingMember = false
            pendingMemberAction = nil
        }
        do {
            switch action {
            case .remove(let profileID):
                try await rooms.removeMember(roomID: roomID, profileID: profileID)
                statusMessage = "Member removed."
            case .ban(let profileID):
                try await rooms.banMember(
                    roomID: roomID,
                    profileID: profileID,
                    bannedBy: viewerID
                )
                statusMessage = "Member banned."
            }
            await refreshMembersAndBans()
            tagStore.invalidate(roomID: roomID)
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func unban(_ ban: RoomBanRecord) async {
        guard canManageRoom else { return }
        isMutatingMember = true
        defer { isMutatingMember = false }
        do {
            try await rooms.unbanMember(roomID: roomID, banID: ban.id)
            statusMessage = "Member unbanned."
            await refreshMembersAndBans()
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func createTag(name: String, colorKey: String) async {
        guard canManageRoom, let viewerID else { return }
        isMutatingTag = true
        defer { isMutatingTag = false }
        do {
            _ = try await rooms.createMemberTag(
                roomID: roomID,
                name: name,
                colorKey: colorKey,
                createdBy: viewerID
            )
            await refreshTags()
            statusMessage = "Tag created."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func updateTag(_ tag: RoomMemberTag) async {
        guard canManageRoom else { return }
        isMutatingTag = true
        defer { isMutatingTag = false }
        do {
            _ = try await rooms.updateMemberTag(tag)
            await refreshTags()
            statusMessage = "Tag updated."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func deleteTag(_ tag: RoomMemberTag) async {
        guard canManageRoom else { return }
        isMutatingTag = true
        defer { isMutatingTag = false }
        do {
            try await rooms.deleteMemberTag(tagID: tag.id, roomID: roomID)
            await refreshTags()
            statusMessage = "Tag deleted."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func toggleTag(_ tag: RoomMemberTag, for member: RoomManagedMember) async {
        guard canManageRoom else { return }
        isMutatingTag = true
        defer { isMutatingTag = false }
        do {
            if member.tags.contains(where: { $0.id == tag.id }) {
                try await rooms.removeMemberTagAssignment(
                    roomID: roomID,
                    profileID: member.profile.id,
                    tagID: tag.id
                )
            } else {
                try await rooms.assignMemberTag(
                    roomID: roomID,
                    profileID: member.profile.id,
                    tagID: tag.id
                )
            }
            await refreshTags()
            ExperienceHaptics.play(.selection)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func openProfile(_ profileID: ProfileID) {
        navigationCoordinator?.open(navigationHost.profile(profileID))
    }

    func refreshChannels() async {
        do {
            channels = try await rooms.channels(roomID: roomID)
                .sorted { $0.position < $1.position }
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
        }
    }

    func createChannel(name: String, allowMembersChat: Bool) async -> Bool {
        guard canManageRoom else { return false }
        isMutatingChannel = true
        defer { isMutatingChannel = false }
        do {
            let channel = try await rooms.createChannel(
                roomID: roomID,
                request: RoomChannelCreateRequest(name: name, allowMembersChat: allowMembersChat)
            )
            channels.append(channel)
            channels.sort { $0.position < $1.position }
            RoomMetadataSync.channelsDidChange(roomID: roomID)
            statusMessage = "Channel created."
            ExperienceHaptics.play(.success)
            return true
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
            return false
        }
    }

    func updateChannel(
        _ channel: RoomChannel,
        name: String,
        allowMembersChat: Bool
    ) async -> Bool {
        guard canManageRoom else { return false }
        isMutatingChannel = true
        defer { isMutatingChannel = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await rooms.updateChannel(
                channelID: channel.id,
                request: RoomChannelUpdateRequest(
                    name: trimmed,
                    allowMembersChat: allowMembersChat
                )
            )
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                channels[index] = updated
            }
            channels.sort { $0.position < $1.position }
            RoomMetadataSync.channelsDidChange(roomID: roomID)
            statusMessage = "Channel saved."
            ExperienceHaptics.play(.success)
            return true
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
            return false
        }
    }

    func requestDeleteChannel(_ channel: RoomChannel) async {
        guard canManageRoom, channels.count > RoomChannelValidation.minCount else {
            statusMessage = "You must have at least one channel."
            return
        }
        do {
            let count = try await rooms.channelMessageCount(
                roomID: roomID,
                channelID: channel.id,
                channelName: channel.name
            )
            if count > 0 {
                pendingChannelDelete = .withMessages(channel.id, messageCount: count)
            } else {
                pendingChannelDelete = .empty(channel.id)
            }
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
        }
    }

    func confirmDeleteChannel(_ channelID: RoomChannelID) async {
        guard canManageRoom, let channel = channels.first(where: { $0.id == channelID }) else { return }
        isMutatingChannel = true
        defer {
            isMutatingChannel = false
            pendingChannelDelete = nil
        }
        do {
            try await rooms.deleteChannel(
                roomID: roomID,
                channelID: channel.id,
                channelName: channel.name
            )
            channels.removeAll { $0.id == channel.id }
            RoomMetadataSync.channelsDidChange(roomID: roomID)
            statusMessage = "Channel deleted."
            ExperienceHaptics.play(.success)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    func moveChannel(_ channel: RoomChannel, direction: Int) async {
        guard canManageRoom else { return }
        let sorted = channels.sorted { $0.position < $1.position }
        guard let index = sorted.firstIndex(where: { $0.id == channel.id }) else { return }
        let targetIndex = index + direction
        guard sorted.indices.contains(targetIndex) else { return }
        let other = sorted[targetIndex]
        isMutatingChannel = true
        defer { isMutatingChannel = false }
        do {
            _ = try await rooms.updateChannel(
                channelID: channel.id,
                request: RoomChannelUpdateRequest(position: other.position)
            )
            _ = try await rooms.updateChannel(
                channelID: other.id,
                request: RoomChannelUpdateRequest(position: channel.position)
            )
            await refreshChannels()
            RoomMetadataSync.channelsDidChange(roomID: roomID)
        } catch {
            statusMessage = ConversationThreadSupport.message(for: error)
        }
    }

    func managedMember(for profileID: ProfileID) -> RoomManagedMember? {
        members.first { $0.profile.id == profileID }
    }

    private func performLoad() async {
        phase = .loading
        viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        let priorPendingPreview = pendingImagePreview
        let priorPendingData = pendingImageData
        let priorMarksRemoval = marksImageForRemoval
        do {
            let loaded = try await rooms.room(id: roomID)
            await refreshChannels()
            applyRoomSnapshot(loaded, channels: channels)
            if priorPendingPreview != nil {
                pendingImagePreview = priorPendingPreview
                pendingImageData = priorPendingData
                marksImageForRemoval = priorMarksRemoval
            }
            guard canManageRoom else {
                phase = .failed("You don't have permission to manage this Trade Room.")
                loadTask = nil
                return
            }
            try await tagStore.hydrate(roomID: roomID, repository: rooms)
            tags = tagStore.tags(for: roomID)
            await refreshMembersAndBans()
            await refreshJoinRequests()
            phase = .loaded
        } catch {
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
        loadTask = nil
    }
}
