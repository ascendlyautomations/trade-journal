import Foundation
import Observation
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

    var name = ""
    var descriptionText = ""
    var showsOnProfile = true
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
        phase == .ready && existingOwnedRoom == nil && !trimmedName.isEmpty
    }

    var isSubmitting: Bool {
        phase == .creating
    }

    var hasUnsavedChanges: Bool {
        !trimmedName.isEmpty
            || !trimmedDescription.isEmpty
            || imageData != nil
            || showsOnProfile == false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func setImage(_ image: UIImage?) {
        guard let image else {
            imageData = nil
            imagePreview = nil
            return
        }
        imagePreview = image
        imageData = MediaImagePreparation.jpegData(from: image)
    }

    func clearImage() {
        imageData = nil
        imagePreview = nil
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
        if name.isEmpty {
            let username = viewerProfile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !username.isEmpty {
                name = "\(username)'s Room"
            }
        }
        phase = .ready
    }

    private func performCreate() async {
        formError = nil
        guard validate() else {
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
            var imageURL: String?
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
                imageURL = reference.id
            }

            let room = try await rooms.createRoom(
                request: RoomCreateRequest(
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    imageURL: imageURL,
                    showsOnProfile: showsOnProfile
                ),
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

    private func validate() -> Bool {
        if trimmedName.isEmpty {
            formError = "Room name is required."
            return false
        }
        if trimmedName.count > RoomCreateRequest.Validation.nameMaxLength {
            formError = "Room name must be \(RoomCreateRequest.Validation.nameMaxLength) characters or fewer."
            return false
        }
        if trimmedDescription.count > RoomCreateRequest.Validation.descriptionMaxLength {
            formError = "Description must be \(RoomCreateRequest.Validation.descriptionMaxLength) characters or fewer."
            return false
        }
        formError = nil
        return true
    }

    private func applyCreatedRoomLocally(_ room: TradeRoom, viewerID: ProfileID) {
        detailCache.seedOwnedTradeRoom(room, for: viewerID)

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
