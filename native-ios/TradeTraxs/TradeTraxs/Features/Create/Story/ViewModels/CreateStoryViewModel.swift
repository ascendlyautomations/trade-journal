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
    private let contentDrafts: (any ContentDraftRepository)?
    private let onPublished: (Story) -> Void
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var publishTask: Task<Void, Never>?
    private var hasPrepared = false
    private(set) var isPostingStory = false
    private(set) var isSavingDraft = false
    private(set) var restoredCanvas: StoryCanvasState?
    private var activeDraftID: UUID?
    private var pendingStoryDraft: StoryComposerDraftState?
    private var retainedImagePath: String?
    private var retainedVideoPath: String?
    private var didClearDraftMedia = false

    init(
        feed: any FeedRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        uploadServices: GlobalUploadServices,
        contentDrafts: (any ContentDraftRepository)? = nil,
        restoredDraft: ContentDraft? = nil,
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
        self.contentDrafts = contentDrafts
        self.onPublished = onPublished
        self.onDismiss = onDismiss
        if let restoredDraft, restoredDraft.type == .story {
            applyStoryDraft(restoredDraft)
        }
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
        restoredCanvas = nil
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
        restoredCanvas = nil
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
        restoredCanvas = nil
        pendingVideoTextOverlays = []
        didClearDraftMedia = true
        formError = nil
    }

    var showsSaveDraft: Bool {
        contentDrafts != nil && ExploreModeSupport.canWriteContent
    }

    var canSaveDraft: Bool {
        guard showsSaveDraft, !isSavingDraft, phase != .publishing else { return false }
        if sourceImage != nil || localVideoFileURL != nil || imageData != nil { return true }
        if !didClearDraftMedia, retainedImagePath != nil || retainedVideoPath != nil { return true }
        return restoredCanvas?.textOverlays.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
    }

    func saveDraft(canvas: StoryCanvasState? = nil) {
        guard showsSaveDraft, !isSavingDraft, let contentDrafts else { return }
        let canvas = canvas ?? restoredCanvas ?? StoryCanvasState()
        let hasText = canvas.textOverlays.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasMedia = sourceImage != nil
            || localVideoFileURL != nil
            || (!didClearDraftMedia && (retainedImagePath != nil || retainedVideoPath != nil))
        guard hasText || hasMedia else {
            formError = "Nothing to save yet."
            return
        }
        isSavingDraft = true
        formError = nil
        let draftID = activeDraftID ?? UUID()
        let image = sourceImage
        let videoURL = localVideoFileURL
        let videoType = contentType
        let fileName = originalFileName
        let previousImage = retainedImagePath
        let previousVideo = retainedVideoPath
        let cleared = didClearDraftMedia
        Task {
            do {
                var state = StoryComposerDraftState()
                state.fileName = fileName
                state.imageScale = Double(canvas.imageScale)
                state.imageOffsetWidth = Double(canvas.imageOffset.width)
                state.imageOffsetHeight = Double(canvas.imageOffset.height)
                state.textOverlays = canvas.textOverlays.map(StoryTextOverlayRecord.init)
                if let image, let jpeg = MediaImagePreparation.storyJPEGData(from: image) {
                    state.mediaKind = "image"
                    state.contentType = "image/jpeg"
                    state.imageStoragePath = try await contentDrafts.uploadDraftImage(draftID: draftID, data: jpeg)
                    state.videoStoragePath = nil
                    await contentDrafts.deleteDraftMedia(paths: [previousImage, previousVideo].compactMap { $0 }.filter { $0 != state.imageStoragePath })
                } else if let videoURL {
                    state.mediaKind = "video"
                    state.contentType = videoType.isEmpty ? "video/mp4" : videoType
                    state.videoStoragePath = try await contentDrafts.uploadDraftVideo(
                        draftID: draftID,
                        fileURL: videoURL,
                        contentType: state.contentType
                    )
                    state.imageStoragePath = nil
                    await contentDrafts.deleteDraftMedia(paths: [previousImage, previousVideo].compactMap { $0 }.filter { $0 != state.videoStoragePath })
                } else if cleared {
                    await contentDrafts.deleteDraftMedia(paths: [previousImage, previousVideo].compactMap { $0 })
                } else {
                    state.imageStoragePath = previousImage
                    state.videoStoragePath = previousVideo
                    state.mediaKind = previousVideo != nil ? "video" : "image"
                    state.contentType = videoType
                }
                var payload = ContentDraftPayload()
                payload.story = state
                guard !payload.isMeaningfullyEmpty else {
                    isSavingDraft = false
                    formError = "Nothing to save yet."
                    return
                }
                let saved = try await contentDrafts.saveDraft(
                    ContentDraft(
                        id: draftID,
                        userID: await session.currentUserID ?? UserID(""),
                        type: .story,
                        payload: payload,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
                activeDraftID = saved.id
                isSavingDraft = false
                SaveSuccessConfirmationCenter.shared.present("Draft saved")
                onDismiss()
            } catch {
                isSavingDraft = false
                formError = UserFacingError.message(for: error)
            }
        }
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
            noteDraftPublished(jobID: jobID)
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
        noteDraftPublished(jobID: jobID)
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

        await restorePendingStoryDraftIfNeeded()
        phase = .ready
    }

    private func noteDraftPublished(jobID: String) {
        guard let activeDraftID, let contentDrafts else { return }
        ContentDraftPublicationCleanup.shared.track(
            jobID: jobID,
            draftID: activeDraftID,
            repository: contentDrafts
        )
    }

    private func applyStoryDraft(_ draft: ContentDraft) {
        guard let state = draft.payload.story else { return }
        activeDraftID = draft.id
        pendingStoryDraft = state
        retainedImagePath = state.imageStoragePath
        retainedVideoPath = state.videoStoragePath
        contentType = state.contentType
        originalFileName = state.fileName
    }

    private func restorePendingStoryDraftIfNeeded() async {
        guard let state = pendingStoryDraft else { return }
        pendingStoryDraft = nil
        do {
            if let path = state.videoStoragePath {
                let data = try await ContentDraftMediaDownload.imageData(
                    path: path,
                    session: session,
                    objectStorage: objectStorage
                )
                let ext = state.contentType == "video/quicktime" ? "mov" : "mp4"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(draftMediaToken()).\(ext)")
                try data.write(to: url, options: .atomic)
                localVideoFileURL = url
                contentType = state.contentType
                originalFileName = state.fileName
            } else if let path = state.imageStoragePath {
                let data = try await ContentDraftMediaDownload.imageData(
                    path: path,
                    session: session,
                    objectStorage: objectStorage
                )
                guard let image = UIImage(data: data) else { return }
                sourceImage = image
                contentType = "image/jpeg"
                originalFileName = state.fileName
            }
            restoredCanvas = StoryCanvasState(
                imageScale: CGFloat(state.imageScale),
                imageOffset: CGSize(width: state.imageOffsetWidth, height: state.imageOffsetHeight),
                textOverlays: state.textOverlays.map { $0.storyTextOverlay() },
                selectedTextID: nil
            )
            didClearDraftMedia = false
        } catch {
            formError = "Couldn't restore the draft story."
        }
    }

    private func draftMediaToken() -> String {
        activeDraftID?.uuidString ?? UUID().uuidString
    }
}
