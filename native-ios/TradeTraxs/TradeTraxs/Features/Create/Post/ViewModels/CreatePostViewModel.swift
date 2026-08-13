import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class CreatePostViewModel {
    enum Phase: Equatable {
        case idle
        case ready
        case publishing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var formError: String?
    private(set) var isUploadingMedia = false

    var bodyText = ""
    var imageData: Data?
    var imagePreview: UIImage?

    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var publishTask: Task<Void, Never>?
    private var hasPrepared = false

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onDismiss: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.session = session
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.onDismiss = onDismiss
    }

    var hasUnsavedChanges: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || imageData != nil
    }

    var canPublish: Bool {
        phase != .publishing && phase != .idle
    }

    func loadIfNeeded() {
        guard !hasPrepared else { return }
        hasPrepared = true
        Task { await prepare() }
    }

    func retryLoad() {
        hasPrepared = false
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

    func publish() {
        guard canPublish, publishTask == nil else { return }
        publishTask = Task { await performPublish() }
    }

    func dismissRequested() {
        onDismiss()
    }

    // MARK: - Private

    private func prepare() async {
        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }
        guard viewerID != nil else {
            phase = .failed("Sign in to create a post.")
            return
        }
        phase = .ready
    }

    private func performPublish() async {
        formError = nil
        guard validate() else {
            publishTask = nil
            return
        }
        guard let viewerID else {
            formError = "Sign in to create a post."
            publishTask = nil
            return
        }

        phase = .publishing
        var uploadedStoragePath: String?
        do {
            let content = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            let post: Post
            if viewerID.rawValue.hasPrefix("dev.") {
                var fixture = CreatePostFixtures.samplePost(author: viewerID, body: content)
                if imageData != nil {
                    fixture.media = [
                        MediaReference(id: "dev/create-post.jpg", kind: .image, altText: nil)
                    ]
                }
                post = fixture
            } else {
                var imageURL: String?
                if let imageData {
                    isUploadingMedia = true
                    let uploaded = try await uploadImage(imageData, viewerID: viewerID)
                    uploadedStoragePath = uploaded.storagePath
                    imageURL = uploaded.publicURL
                    isUploadingMedia = false
                }
                post = try await profiles.createWallPost(
                    authorID: viewerID,
                    content: content,
                    imageURL: imageURL
                )
            }

            ContentMutationStore.shared.notePostCreated(post.id)
            ExperienceHaptics.play(.success)
            phase = .ready
            onDismiss()
        } catch {
            isUploadingMedia = false
            if let path = uploadedStoragePath {
                try? await objectStorage.delete(
                    bucket: StorageBucket.profilePosts.rawValue,
                    path: path
                )
            }
            phase = .ready
            formError = "Couldn't publish post. Check your connection and try again."
        }
        publishTask = nil
    }

    private func validate() -> Bool {
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && imageData == nil {
            formError = "Add text or an image to publish."
            return false
        }
        return true
    }

    private struct UploadedImage {
        var storagePath: String
        var publicURL: String
    }

    private func uploadImage(_ data: Data, viewerID: ProfileID) async throws -> UploadedImage {
        let path = "\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.profilePosts.rawValue,
                path: path,
                data: data,
                contentType: "image/jpeg",
                purpose: .postImage
            )
        )
        let publicURL = objectStorage.publicURL(
            bucket: StorageBucket.profilePosts.rawValue,
            path: reference.id
        )?.absoluteString ?? reference.id
        return UploadedImage(storagePath: reference.id, publicURL: publicURL)
    }
}
