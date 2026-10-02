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
    /// Original picked image — preserved separately from the rendered upload.
    private(set) var sourceImage: UIImage?
    private(set) var localVideoFileURL: URL?
    private var pendingVideoTextOverlays: [StoryTextOverlayRecord] = []
    private(set) var contentType = "image/jpeg"
    private(set) var originalFileName = "story.jpg"

    private(set) var viewerProfile: Profile?

    private let feed: any FeedRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let uploadServices: GlobalUploadServices
    private let onPublished: (Story) -> Void
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var publishTask: Task<Void, Never>?
    private var hasPrepared = false
    private(set) var isPostingStory = false

    init(
        feed: any FeedRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        uploadServices: GlobalUploadServices,
        onPublished: @escaping (Story) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.feed = feed
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.uploadServices = uploadServices
        self.onPublished = onPublished
        self.onDismiss = onDismiss
    }

    var hasUnsavedChanges: Bool {
        sourceImage != nil || imageData != nil || localVideoFileURL != nil
    }

    var canPublish: Bool {
        phase == .ready && (imageData != nil || localVideoFileURL != nil)
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

    func setSourceImage(_ image: UIImage, fileName: String = "story.jpg") {
        guard canChangeMedia else { return }
        formError = nil
        localVideoFileURL = nil
        sourceImage = image
        imagePreview = nil
        imageData = nil
        originalFileName = fileName.hasSuffix(".jpg") || fileName.hasSuffix(".jpeg")
            ? fileName
            : "story.jpg"
        contentType = "image/jpeg"
        if case .idle = phase {
            phase = .ready
        } else if case .failed = phase {
            phase = .ready
        }
    }

    func setSourceVideo(fileURL: URL) async {
        guard canChangeMedia else { return }
        formError = nil
        do {
            _ = try await StoryMediaDuration.validatedDurationSeconds(at: fileURL)
        } catch {
            formError = UserFacingError.message(for: error)
            return
        }
        sourceImage = nil
        imagePreview = nil
        imageData = nil
        localVideoFileURL = fileURL
        contentType = "video/mp4"
        originalFileName = "story.mp4"
        if case .idle = phase {
            phase = .ready
        } else if case .failed = phase {
            phase = .ready
        }
    }

    func submitRenderedStory(_ rendered: UIImage) {
        guard canChangeMedia else { return }
        formError = nil
        guard let prepared = MediaImagePreparation.storyJPEGData(from: rendered) else {
            formError = "Couldn't prepare story image."
            return
        }
        if let message = StoryUploadValidation.validate(
            data: prepared,
            contentType: "image/jpeg",
            fileName: originalFileName
        ) {
            formError = message
            return
        }
        imagePreview = rendered
        imageData = prepared
        contentType = "image/jpeg"
    }

    /// Renders story from the editor and enqueues publish via ``GlobalUploadCoordinator``.
    func postRenderedStory(_ rendered: UIImage) {
        guard canChangeMedia, !isPostingStory else { return }
        isPostingStory = true
        defer { isPostingStory = false }
        submitRenderedStory(rendered)
        guard imageData != nil else { return }
        publish()
    }

    func setImage(_ image: UIImage, fileName: String = "story.jpg") {
        setSourceImage(image, fileName: fileName)
    }

    func clearImage() {
        guard canChangeMedia else { return }
        sourceImage = nil
        imagePreview = nil
        imageData = nil
        localVideoFileURL = nil
        pendingVideoTextOverlays = []
        formError = nil
    }

    func postVideoStory(textOverlays: [StoryTextOverlay]) {
        guard canChangeMedia, !isPostingStory else { return }
        isPostingStory = true
        defer { isPostingStory = false }
        pendingVideoTextOverlays = textOverlays.map(StoryTextOverlayRecord.init)
        publish()
    }

    func reportPickerError(_ message: String) {
        formError = message
    }

    func publish() {
        guard canPublish, publishTask == nil else { return }
        formError = nil
        guard let viewerID else {
            formError = "Missing story media."
            return
        }

        if let localVideoFileURL {
            let jobID = GlobalUploadCoordinator.shared.enqueueStory(
                spec: StoryUploadSpec(
                    authorID: viewerID,
                    imageData: nil,
                    localVideoFileURL: localVideoFileURL,
                    contentType: contentType,
                    originalFileName: originalFileName,
                    textOverlays: pendingVideoTextOverlays
                ),
                services: uploadServices,
                onSuccess: onPublished
            )
            clearImage()
            phase = .ready
            onDismiss()
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: .story,
                event: .composerDismissed,
                taskCancelled: Task.isCancelled
            )
            return
        }

        guard let imageData else {
            formError = "Missing story image."
            return
        }
        if let message = StoryUploadValidation.validate(
            data: imageData,
            contentType: contentType,
            fileName: originalFileName
        ) {
            formError = message
            return
        }

        let jobID = GlobalUploadCoordinator.shared.enqueueStory(
            spec: StoryUploadSpec(
                authorID: viewerID,
                imageData: imageData,
                localVideoFileURL: nil,
                contentType: contentType,
                originalFileName: originalFileName
            ),
            services: uploadServices,
            onSuccess: onPublished
        )
        clearImage()
        phase = .ready
        onDismiss()
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: .story,
            event: .composerDismissed,
            taskCancelled: Task.isCancelled
        )
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

        phase = .ready
    }
}
