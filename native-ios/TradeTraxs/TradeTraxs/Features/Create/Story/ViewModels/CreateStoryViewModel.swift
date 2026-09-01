import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class CreateStoryViewModel {
    enum Phase: Equatable {
        case idle
        case ready
        case publishing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var formError: String?
    private(set) var uploadProgress: Double = 0
    private(set) var uploadStage = ""

    private(set) var imagePreview: UIImage?
    private(set) var imageData: Data?
    private(set) var contentType = "image/jpeg"
    private(set) var originalFileName = "story.jpg"

    private(set) var viewerProfile: Profile?

    private let feed: any FeedRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let onPublished: (Story) -> Void
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var publishTask: Task<Void, Never>?
    private var hasPrepared = false

    init(
        feed: any FeedRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onPublished: @escaping (Story) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.feed = feed
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.onPublished = onPublished
        self.onDismiss = onDismiss
    }

    var hasUnsavedChanges: Bool {
        imageData != nil
    }

    var canPublish: Bool {
        phase == .ready && imageData != nil
    }

    var canChangeMedia: Bool {
        phase == .ready
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

    func setImage(_ image: UIImage, fileName: String = "story.jpg") {
        guard canChangeMedia else { return }
        formError = nil
        guard let prepared = MediaImagePreparation.storyJPEGData(from: image) else {
            formError = "Couldn't prepare image."
            return
        }
        if let message = StoryUploadValidation.validate(
            data: prepared,
            contentType: "image/jpeg",
            fileName: fileName
        ) {
            formError = message
            return
        }
        imagePreview = image
        imageData = prepared
        contentType = "image/jpeg"
        originalFileName = fileName.hasSuffix(".jpg") || fileName.hasSuffix(".jpeg")
            ? fileName
            : "story.jpg"
        if case .idle = phase {
            phase = .ready
        } else if case .failed = phase {
            phase = .ready
        }
    }

    func clearImage() {
        guard canChangeMedia else { return }
        imagePreview = nil
        imageData = nil
        formError = nil
    }

    func reportPickerError(_ message: String) {
        formError = message
    }

    func publish() {
        guard canPublish, publishTask == nil else { return }
        publishTask = Task { await performPublish() }
    }

    func dismissRequested() {
        guard phase != .publishing else { return }
        onDismiss()
    }

    // MARK: - Private

    private func prepare() async {
        guard let raw = await session.currentUserID?.rawValue else {
            phase = .failed("Sign in to create a story.")
            return
        }
        let viewer = ProfileID(raw)
        viewerID = viewer

        if let cached = detailCache.profile(id: viewer) {
            viewerProfile = cached
        } else if let fixture = FollowListFixtures.profile(id: viewer) {
            viewerProfile = fixture
            detailCache.seed(fixture)
        } else if let loaded = try? await profiles.profile(id: viewer) {
            viewerProfile = loaded
            detailCache.seed(loaded)
        }

        if imageData != nil {
            phase = .ready
        } else {
            phase = .ready
        }
    }

    private func performPublish() async {
        formError = nil
        guard let viewerID, let imageData else {
            formError = "Missing story image."
            publishTask = nil
            return
        }
        if let message = StoryUploadValidation.validate(
            data: imageData,
            contentType: contentType,
            fileName: originalFileName
        ) {
            formError = message
            publishTask = nil
            return
        }

        phase = .publishing
        uploadProgress = 0
        uploadStage = "Preparing story…"

        do {
            let story: Story
            if viewerID.rawValue.hasPrefix("dev.") {
                story = Story(
                    id: StoryID("dev-story-\(UUID().uuidString.prefix(8))"),
                    authorProfileID: viewerID,
                    media: MediaReference(
                        id: "dev/story-preview.jpg",
                        kind: .image,
                        altText: nil
                    ),
                    expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
                    createdAt: Date(),
                    viewerHasSeen: false
                )
                uploadProgress = 1
            } else {
                story = try await StoryPublishPipeline.publish(
                    imageData: imageData,
                    contentType: contentType,
                    originalFileName: originalFileName,
                    authorID: viewerID,
                    feed: feed,
                    uploadService: uploadService,
                    objectStorage: objectStorage
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.uploadProgress = progress
                        if progress < 0.2 {
                            self?.uploadStage = "Preparing story…"
                        } else if progress < 0.85 {
                            self?.uploadStage = "Uploading media…"
                        } else if progress < 0.98 {
                            self?.uploadStage = "Publishing story…"
                        } else {
                            self?.uploadStage = "Finishing…"
                        }
                    }
                }
            }

            detailCache.seed(story)
            ContentMutationStore.shared.noteStoryCreated(story)
            ExperienceHaptics.play(.success)
            phase = .ready
            onPublished(story)
        } catch let error as AppError {
            phase = .ready
            formError = UserFacingError.message(for: error)
        } catch {
            phase = .ready
            formError = UserFacingError.message(for: error)
        }
        publishTask = nil
    }
}
