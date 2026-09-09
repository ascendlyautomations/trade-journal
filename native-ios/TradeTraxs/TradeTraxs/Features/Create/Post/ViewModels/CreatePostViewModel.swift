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
    private(set) var viewerProfile: Profile?

    var bodyText = ""
    private(set) var finalImage: UIImage?
    private(set) var finalImageData: Data?

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
            || finalImageData != nil
    }

    var canPublish: Bool {
        phase != .publishing && phase != .idle
    }

    /// True when the draft has text or an image — used to enable the Publish button.
    var hasValidDraft: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || finalImageData != nil
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

    func setImage(_ result: ImageCropSelectionResult) {
        guard let applied = ComposerCropImageState.apply(result) else { return }
        finalImage = applied.finalImage
        finalImageData = applied.uploadData
    }

    func setImage(_ image: UIImage?) {
        guard let image else {
            clearImage()
            return
        }
        let pixelSize = MediaImageOrientation.pixelSize(of: image)
        setImage(
            ImageCropSelectionResult(
                image: image,
                aspectMode: .original,
                sourcePixelSize: pixelSize
            )
        )
    }

    func clearImage() {
        finalImageData = nil
        finalImage = nil
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
        guard let viewerID else {
            phase = .failed("Sign in to create a post.")
            return
        }
        viewerProfile = try? await profiles.profile(id: viewerID)
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

        let pixelSize = finalImage.map { MediaImageOrientation.pixelSize(of: $0) }
        let caption = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        PostPublishProbe.logStarted(
            flow: "profile_post",
            captionLength: caption.count,
            imagePresent: finalImage != nil,
            imageBytes: finalImageData?.count,
            imagePixelSize: pixelSize,
            cropMetadata: nil
        )

        if let finalImage, let finalImageData {
            PostImageUploadProbe.log(finalImage: finalImage, uploadData: finalImageData)
            guard !finalImageData.isEmpty else {
                let error = AppError.unknown(message: "Image encoding produced empty JPEG data.")
                PostPublishProbe.logFailed(stage: .imageEncode, error: error)
                formError = PostPublishProbe.userFacingMessage(for: .imageEncode, error: error)
                publishTask = nil
                return
            }
            PostPublishProbe.logImageEncode(
                byteCount: finalImageData.count,
                mimeType: "image/jpeg",
                pixelSize: pixelSize
            )
        }

        phase = .publishing
        var uploadedStoragePath: String?
        var failedStage = PostPublishProbe.Stage.unknown
        do {
            let content = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            let post: Post
            if viewerID.rawValue.hasPrefix("dev.") {
                var fixture = CreatePostFixtures.samplePost(author: viewerID, body: content)
                if finalImageData != nil {
                    fixture.media = [
                        MediaReference(id: "dev/create-post.jpg", kind: .image, altText: nil)
                    ]
                }
                post = fixture
            } else {
                var imageURL: String?
                if let finalImageData {
                    failedStage = .upload
                    isUploadingMedia = true
                    let path = "\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                    PostPublishProbe.logUploadStarted(
                        storagePath: path,
                        bucket: StorageBucket.profilePosts.rawValue
                    )
                    let uploaded = try await uploadImage(finalImageData, viewerID: viewerID, path: path)
                    uploadedStoragePath = uploaded.storagePath
                    imageURL = uploaded.publicURL
                    PostPublishProbe.logUploadSucceeded(path: uploaded.storagePath)
                    isUploadingMedia = false
                }
                failedStage = .databaseInsert
                post = try await profiles.createWallPost(
                    authorID: viewerID,
                    content: content,
                    imageURL: imageURL,
                    imageCrop: nil
                )
            }

            OwnerProfileOptimisticStore.shared.notePostCreated(post)
            ExperienceHaptics.play(.success)
            phase = .ready
            onDismiss()
        } catch {
            isUploadingMedia = false
            if error is DecodingError {
                failedStage = .responseDecode
            }
            PostPublishProbe.logFailed(stage: failedStage, error: error)
            if let path = uploadedStoragePath {
                PostPublishProbe.logNote("cleaning up uploaded storage path=\(path)")
                try? await objectStorage.delete(
                    bucket: StorageBucket.profilePosts.rawValue,
                    path: path
                )
            }
            phase = .ready
            formError = PostPublishProbe.userFacingMessage(for: failedStage, error: error)
        }
        publishTask = nil
    }

    private func validate() -> Bool {
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && finalImageData == nil {
            formError = "Add text or an image to publish."
            return false
        }
        return true
    }

    private struct UploadedImage {
        var storagePath: String
        var publicURL: String
    }

    private func uploadImage(_ data: Data, viewerID: ProfileID, path: String) async throws -> UploadedImage {
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
