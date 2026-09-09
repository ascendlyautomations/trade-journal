import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class CreateRoomViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case creating
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var formError: String?
    private(set) var viewerProfile: Profile?
    private(set) var existingOwnedRoom: TradeRoom?
    private(set) var isUploadingImage = false

    var configuration = TradeRoomConfiguration.defaultDraft(username: nil)
    var imageData: Data?
    var imagePreview: UIImage?

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let uploadService: any UploadService
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let onDismiss: () -> Void
    private let onCreated: (TradeRoom) -> Void

    private var viewerID: ProfileID?
    private var createTask: Task<Void, Never>?
    private var hasPrepared = false

    init(
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        uploadService: any UploadService,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore? = nil,
        onDismiss: @escaping () -> Void,
        onCreated: @escaping (TradeRoom) -> Void
    ) {
        self.rooms = rooms
        self.profiles = profiles
        self.uploadService = uploadService
        self.session = session
        self.detailCache = detailCache
        self.inboxStore = inboxStore ?? .shared
        self.onDismiss = onDismiss
        self.onCreated = onCreated
    }

    var canCreate: Bool {
        phase == .ready && existingOwnedRoom == nil && !configuration.trimmedName.isEmpty
    }

    var isSubmitting: Bool {
        phase == .creating
    }

    var hasUnsavedChanges: Bool {
        configuration.hasUnsavedDraftChanges || imageData != nil
    }

    var showsJoinPolicy: Bool {
        configuration.visibility == .public
    }

    func loadIfNeeded() {
        guard !hasPrepared else { return }
        hasPrepared = true
        Task { await prepare() }
    }

    func retryLoad() {
        hasPrepared = false
        phase = .idle
        loadIfNeeded()
    }

    func setCroppedImage(_ result: ImageCropSelectionResult) {
        guard let applied = ComposerCropImageState.apply(result) else { return }
        imagePreview = applied.finalImage
        imageData = applied.uploadData
    }

    func clearImage() {
        imageData = nil
        imagePreview = nil
    }

    func setVisibility(_ visibility: TradeRoomVisibility) {
        configuration.visibility = visibility
        if visibility == .private {
            configuration.joinPolicy = .open
        }
    }

    func toggleDiscoveryTag(_ tag: String) {
        if configuration.discoveryTags.contains(tag) {
            configuration.discoveryTags.removeAll { $0 == tag }
        } else if configuration.discoveryTags.count < TradeRoomConfigurationValidation.maxDiscoveryTags {
            configuration.discoveryTags.append(tag)
        }
    }

    func addSubRoom() {
        guard configuration.channels.count < TradeRoomConfigurationValidation.maxChannels else { return }
        configuration.channels.append(TradeRoomDraftChannel(name: ""))
    }

    func removeSubRoom(id: UUID) {
        guard configuration.channels.count > 1 else { return }
        configuration.channels.removeAll { $0.id == id }
    }

    func moveSubRooms(from source: IndexSet, to destination: Int) {
        configuration.channels.move(fromOffsets: source, toOffset: destination)
    }

    func create() {
        guard createTask == nil, canCreate else { return }
        createTask = Task { await performCreate() }
    }

    func openExistingOwnedRoom() {
        guard let existingOwnedRoom else { return }
        onDismiss()
        onCreated(existingOwnedRoom)
    }

    func dismissRequested() {
        onDismiss()
    }

    // MARK: - Private

    private func prepare() async {
        phase = .loading
        guard let raw = await session.currentUserID?.rawValue else {
            phase = .failed("Sign in to create a Trade Room.")
            return
        }
        viewerID = ProfileID(raw)
        viewerProfile = try? await profiles.profile(id: ProfileID(raw))
        do {
            existingOwnedRoom = try await rooms.ownedRoom(for: ProfileID(raw))
        } catch {
            existingOwnedRoom = nil
        }
        if configuration.trimmedName.isEmpty {
            configuration = TradeRoomConfiguration.defaultDraft(username: viewerProfile?.username)
        }
        phase = .ready
    }

    private func performCreate() async {
        formError = nil
        if imageData != nil {
            configuration.imageURL = nil
        }
        if let validationError = TradeRoomConfigurationValidation.validate(configuration) {
            formError = validationError
            createTask = nil
            return
        }
        guard let viewerID, let viewerProfile else {
            formError = "Sign in to create a Trade Room."
            createTask = nil
            return
        }

        phase = .creating
        defer {
            createTask = nil
            if phase == .creating {
                phase = .ready
            }
        }

        do {
            if let imageData {
                isUploadingImage = true
                defer { isUploadingImage = false }
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

            let room = try await rooms.createRoom(
                request: RoomCreateRequest(configuration: configuration),
                ownerProfileID: viewerID,
                ownerUsername: viewerProfile.username
            )

            applyCreatedRoomLocally(room, viewerID: viewerID)
            ExperienceHaptics.play(.success)
            onDismiss()
            onCreated(room)
        } catch {
            formError = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.error)
            phase = .ready
        }
    }

    private func applyCreatedRoomLocally(_ room: TradeRoom, viewerID: ProfileID) {
        detailCache.seedOwnedTradeRoom(room, for: viewerID)
        TradeRoomCreationIntent.shared.noteCreatedRoom(room)

        var rooms = inboxStore.rooms
        if !rooms.contains(where: { $0.id == room.id }) {
            var enriched = room
            if enriched.memberCount == nil {
                enriched.memberCount = 1
            }
            rooms.append(enriched)
            inboxStore.replaceRooms(rooms)
        }
    }
}
