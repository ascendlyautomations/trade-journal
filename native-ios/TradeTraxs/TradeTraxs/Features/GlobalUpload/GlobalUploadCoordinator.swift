import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GlobalUploadCoordinator {
    static let shared = GlobalUploadCoordinator()

    private(set) var jobs: [UploadJob] = []
    var isQueuePresented = false

    private var tasks: [String: Task<Void, Never>] = [:]
    private var retryReel: [String: (ReelUploadSpec, GlobalUploadServices)] = [:]
    private var retryPost: [String: (PostUploadSpec, GlobalUploadServices, PostUploadCheckpoint)] = [:]
    private var retryStory: [String: (StoryUploadSpec, GlobalUploadServices, StoryUploadCheckpoint)] = [:]
    private var retryAchievement: [String: (AchievementUploadSpec, GlobalUploadServices, AchievementUploadCheckpoint)] = [:]
    private var retryTrade: [String: (TradeSaveUploadSpec, GlobalUploadServices, TradeSaveUploadCheckpoint)] = [:]
    private var storySuccessHandlers: [String: (Story) -> Void] = [:]
    /// Bumped on every new run / user cancellation so stale continuations cannot publish after terminal cleanup.
    private var jobRunGeneration: [String: UInt64] = [:]
    /// Generation that reached `.completed` — blocks accidental re-starts until explicit retry after `.failed`.
    private var completedGenerations: [String: UInt64] = [:]
    /// In-flight worker generation (at most one active run per job ID).
    private var activeTaskGenerations: [String: UInt64] = [:]
    private var scheduledRemovalTasks: [String: Task<Void, Never>] = [:]
    /// Job IDs fully finalized after success — blocks any accidental re-start of the same upload job.
    private var terminalJobIDs: Set<String> = []

    private enum StartIntent {
        case enqueue
        case retry
    }

    private init() {}

    var barPresentation: GlobalUploadBarPresentation? {
        let visible = jobs.filter { $0.phase != .completed || $0.showsSuccessFlash }
        guard !visible.isEmpty else { return nil }

        let failures = visible.filter { $0.phase == .failed }
        if failures.count == 1, visible.count == 1, let job = failures.first {
            return GlobalUploadBarPresentation(
                line: job.displayLine,
                progress: nil,
                showsRetry: true,
                activeCount: 1
            )
        }

        if visible.count == 1, let job = visible.first {
            return GlobalUploadBarPresentation(
                line: job.displayLine,
                progress: job.progress,
                showsRetry: job.phase == .failed,
                activeCount: 1
            )
        }

        let active = visible.filter { $0.phase != .completed && $0.phase != .failed }
        let weights = active.map(\.aggregateWeight)
        let combined: Double? = {
            guard !weights.isEmpty else { return nil }
            let raw = weights.reduce(0, +) / Double(weights.count)
            guard raw.isFinite else { return nil }
            return min(1, max(0, raw))
        }()
        let line: String
        if let combined {
            line = "Uploading \(active.count) items                     \(Int((combined * 100).rounded()))%"
        } else {
            line = "Uploading \(max(active.count, visible.count)) items…"
        }
        return GlobalUploadBarPresentation(
            line: line,
            progress: combined,
            showsRetry: !failures.isEmpty,
            activeCount: visible.count
        )
    }

    // MARK: - Enqueue

    @discardableResult
    func enqueueReel(spec: ReelUploadSpec, services: GlobalUploadServices) -> String {
        let jobID = spec.publishID
        insertJob(
            UploadJob(
                id: jobID,
                kind: .reel,
                title: "Reel",
                phase: .preparing,
                progress: nil,
                errorMessage: nil,
                completedAt: nil,
                showsSuccessFlash: false
            )
        )
        retryReel[jobID] = (spec, services)
        startTask(jobID: jobID, kind: .reel, intent: .enqueue) { [weak self] generation in
            await self?.runReel(jobID: jobID, spec: spec, services: services, runGeneration: generation)
        }
        return jobID
    }

    @discardableResult
    func enqueuePost(spec: PostUploadSpec, services: GlobalUploadServices) -> String {
        let jobID = UUID().uuidString
        var checkpoint = PostUploadCheckpoint()
        if spec.imageData != nil {
            checkpoint.imageStoragePath = "\(spec.authorID.rawValue)/\(jobID).jpg"
        }
        insertJob(
            UploadJob(
                id: jobID,
                kind: .post,
                title: "Post",
                phase: .preparing,
                progress: nil,
                errorMessage: nil,
                completedAt: nil,
                showsSuccessFlash: false
            )
        )
        retryPost[jobID] = (spec, services, checkpoint)
        startTask(jobID: jobID, kind: .post, intent: .enqueue) { [weak self] generation in
            await self?.runPost(
                jobID: jobID,
                spec: spec,
                services: services,
                checkpoint: checkpoint,
                runGeneration: generation
            )
        }
        return jobID
    }

    @discardableResult
    func enqueueAchievement(spec: AchievementUploadSpec, services: GlobalUploadServices) -> String {
        let jobID = spec.jobID
        insertJob(
            UploadJob(
                id: jobID,
                kind: .achievement,
                title: "Achievement",
                phase: .preparing,
                progress: nil,
                errorMessage: nil,
                completedAt: nil,
                showsSuccessFlash: false
            )
        )
        let achievementCheckpoint = AchievementUploadCheckpoint()
        retryAchievement[jobID] = (spec, services, achievementCheckpoint)
        startTask(jobID: jobID, kind: .achievement, intent: .enqueue) { [weak self] generation in
            await self?.runAchievement(
                jobID: jobID,
                spec: spec,
                services: services,
                checkpoint: achievementCheckpoint,
                runGeneration: generation
            )
        }
        return jobID
    }

    @discardableResult
    func enqueueTrade(
        spec: TradeSaveUploadSpec,
        services: GlobalUploadServices,
        checkpoint: TradeSaveUploadCheckpoint = TradeSaveUploadCheckpoint(
            uploadedScreenshotPublicURL: nil,
            uploadedScreenshotStoragePath: nil,
            savedTradeID: nil,
            clipAttached: false,
            reelLinked: false,
            publicFeedPostCompleted: false,
            reelVideoPublicURL: nil,
            reelVideoStoragePath: nil,
            reelThumbnailPublicURL: nil,
            reelThumbnailStoragePath: nil,
            linkedExistingReelID: nil
        )
    ) -> String {
        let jobID = spec.jobID
        if terminalJobIDs.contains(jobID) {
            #if DEBUG
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: .trade,
                event: .staleRunIgnored,
                taskCancelled: false,
                generation: completedGenerations[jobID],
                detail: "duplicateEnqueueTerminalJob"
            )
            #endif
            return jobID
        }
        if let existing = jobs.first(where: { $0.id == jobID }) {
            if existing.phase == .completed || completedGenerations[jobID] != nil || tasks[jobID] != nil {
                #if DEBUG
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .trade,
                    event: .staleRunIgnored,
                    taskCancelled: false,
                    generation: jobRunGeneration[jobID],
                    detail: "duplicateEnqueue phase=\(existing.phase.rawValue)"
                )
                #endif
                return jobID
            }
        }
        insertJob(
            UploadJob(
                id: jobID,
                kind: .trade,
                title: "Trade",
                phase: .preparing,
                progress: nil,
                errorMessage: nil,
                completedAt: nil,
                showsSuccessFlash: false
            )
        )
        retryTrade[jobID] = (spec, services, checkpoint)
        #if DEBUG
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: .trade,
            event: .enqueued,
            taskCancelled: false,
            generation: (jobRunGeneration[jobID] ?? 0) + 1
        )
        #endif
        startTask(jobID: jobID, kind: .trade, intent: .enqueue) { [weak self] generation in
            await self?.runTrade(
                jobID: jobID,
                spec: spec,
                services: services,
                checkpoint: checkpoint,
                runGeneration: generation
            )
        }
        return jobID
    }

    @discardableResult
    func enqueueStory(
        spec: StoryUploadSpec,
        services: GlobalUploadServices,
        onSuccess: ((Story) -> Void)? = nil
    ) -> String {
        let jobID = UUID().uuidString
        var storySpec = spec
        storySpec.storagePath = StoryPublishPipeline.makeJobStoragePath(
            jobID: jobID,
            authorID: spec.authorID,
            originalFileName: spec.originalFileName ?? "story.jpg",
            contentType: spec.contentType
        )
        storySuccessHandlers[jobID] = onSuccess
        insertJob(
            UploadJob(
                id: jobID,
                kind: .story,
                title: "Story",
                phase: .preparing,
                progress: nil,
                errorMessage: nil,
                completedAt: nil,
                showsSuccessFlash: false
            )
        )
        retryStory[jobID] = (storySpec, services, StoryUploadCheckpoint())
        startTask(jobID: jobID, kind: .story, intent: .enqueue) { [weak self] generation in
            await self?.runStory(jobID: jobID, spec: storySpec, services: services, runGeneration: generation)
        }
        return jobID
    }

    func retry(jobID: String) {
        guard jobs.first(where: { $0.id == jobID })?.phase == .failed else { return }
        terminalJobIDs.remove(jobID)
        completedGenerations.removeValue(forKey: jobID)
        if let (spec, services) = retryReel[jobID] {
            updateJob(jobID) { job in
                job.phase = .preparing
                job.progress = nil
                job.errorMessage = nil
                job.showsSuccessFlash = false
            }
            startTask(jobID: jobID, kind: .reel, intent: .retry) { [weak self] generation in
                await self?.runReel(jobID: jobID, spec: spec, services: services, runGeneration: generation)
            }
            return
        }
        if let (spec, services, checkpoint) = retryPost[jobID] {
            updateJob(jobID) { job in
                job.phase = .preparing
                job.progress = nil
                job.errorMessage = nil
            }
            startTask(jobID: jobID, kind: .post, intent: .retry) { [weak self] generation in
                await self?.runPost(
                    jobID: jobID,
                    spec: spec,
                    services: services,
                    checkpoint: checkpoint,
                    runGeneration: generation
                )
            }
            return
        }
        if let (spec, services, _) = retryStory[jobID] {
            updateJob(jobID) { job in
                job.phase = .preparing
                job.progress = nil
                job.errorMessage = nil
            }
            startTask(jobID: jobID, kind: .story, intent: .retry) { [weak self] generation in
                await self?.runStory(jobID: jobID, spec: spec, services: services, runGeneration: generation)
            }
            return
        }
        if let (spec, services, checkpoint) = retryAchievement[jobID] {
            updateJob(jobID) { job in
                job.phase = .preparing
                job.progress = nil
                job.errorMessage = nil
                job.showsSuccessFlash = false
            }
            startTask(jobID: jobID, kind: .achievement, intent: .retry) { [weak self] generation in
                await self?.runAchievement(
                    jobID: jobID,
                    spec: spec,
                    services: services,
                    checkpoint: checkpoint,
                    runGeneration: generation
                )
            }
            return
        }
        if let (spec, services, checkpoint) = retryTrade[jobID] {
            updateJob(jobID) { job in
                job.phase = .preparing
                job.progress = nil
                job.errorMessage = nil
                job.showsSuccessFlash = false
            }
            startTask(jobID: jobID, kind: .trade, intent: .retry) { [weak self] generation in
                await self?.runTrade(
                    jobID: jobID,
                    spec: spec,
                    services: services,
                    checkpoint: checkpoint,
                    runGeneration: generation
                )
            }
        }
    }

    func remove(jobID: String) {
        let kind = jobs.first(where: { $0.id == jobID })?.kind ?? .post
        if let job = jobs.first(where: { $0.id == jobID }), job.phase == .completed {
            scheduledRemovalTasks[jobID]?.cancel()
            scheduledRemovalTasks.removeValue(forKey: jobID)
            let generation = jobRunGeneration[jobID] ?? completedGenerations[jobID] ?? 0
            finalizeCompletedJob(jobID: jobID, runGeneration: generation, kind: kind)
            return
        }
        cancelActiveJob(jobID: jobID, kind: kind, cancelSource: "GlobalUploadCoordinator.remove")
    }

    private func cancelActiveJob(jobID: String, kind: UploadJobKind, cancelSource: String) {
        invalidateJobRun(jobID: jobID)
        completedGenerations.removeValue(forKey: jobID)
        activeTaskGenerations.removeValue(forKey: jobID)
        scheduledRemovalTasks[jobID]?.cancel()
        scheduledRemovalTasks.removeValue(forKey: jobID)
        if tasks[jobID] != nil {
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: kind,
                event: .cancelled,
                taskCancelled: tasks[jobID]?.isCancelled ?? false,
                generation: jobRunGeneration[jobID],
                cancelSource: cancelSource
            )
        }
        tasks[jobID]?.cancel()
        tasks.removeValue(forKey: jobID)
        clearRetryState(jobID: jobID)
        jobs.removeAll { $0.id == jobID }
    }

    /// Logout / account switch — cancel uploads and drop session-scoped job state.
    func invalidateForSessionChange() {
        releasePendingUploadResources()
        purgeAllJobs(reason: "sessionChange")
        isQueuePresented = false
    }

    func resetForTesting() {
        invalidateForSessionChange()
    }

    private func releasePendingUploadResources() {
        for (_, (spec, _)) in retryReel {
            cleanupReelFiles(spec.snapshot.asDraft)
        }
    }

    private func purgeAllJobs(reason: String) {
        for id in Array(tasks.keys) {
            cancelActiveJob(
                jobID: id,
                kind: jobs.first(where: { $0.id == id })?.kind ?? .trade,
                cancelSource: "GlobalUploadCoordinator.\(reason)"
            )
        }
        for job in jobs where job.phase == .completed {
            let generation = jobRunGeneration[job.id] ?? completedGenerations[job.id] ?? 0
            finalizeCompletedJob(jobID: job.id, runGeneration: generation, kind: job.kind)
        }
        jobs.removeAll()
        completedGenerations.removeAll()
        activeTaskGenerations.removeAll()
        jobRunGeneration.removeAll()
        terminalJobIDs.removeAll()
        scheduledRemovalTasks.values.forEach { $0.cancel() }
        scheduledRemovalTasks.removeAll()
    }

    // MARK: - Runners

    private func runReel(
        jobID: String,
        spec: ReelUploadSpec,
        services: GlobalUploadServices,
        runGeneration: UInt64
    ) async {
        guard jobRunIsLive(jobID: jobID, generation: runGeneration, stage: "runReel.entry") else { return }
        await registerProgress(jobID: jobID, phase: .encoding) { [weak self] fraction in
            self?.updateJob(jobID) { job in
                job.phase = .encoding
                job.progress = fraction * 0.45
            }
        }

        let draft = spec.snapshot.asDraft
        do {
            if let tradeID = spec.snapshot.linkedTradeID {
                updateJob(jobID) { $0.phase = .preparing }
                if try await services.feed.tradeHasAttachedReel(tradeID) {
                    throw AppError.domain(.conflict(message: "This trade already has a clip attached."))
                }
            }

            let reel: Reel
            if spec.authorID.rawValue.hasPrefix("dev.") {
                reel = CreateReelFixtures.sampleReel(
                    author: spec.authorID,
                    tradeID: spec.snapshot.linkedTradeID
                )
            } else {
                reel = try await UploadProgressContext.$jobID.withValue(jobID) {
                    try await ReelPublishPipeline.publish(
                        publishID: jobID,
                        draft: draft,
                        authorID: spec.authorID,
                        tradeID: spec.snapshot.linkedTradeID,
                        tradeIsPublic: spec.tradeIsPublic,
                        feed: services.feed,
                        uploadService: services.uploadService,
                        objectStorage: services.objectStorage,
                        onProgress: { value in
                            Task { @MainActor [weak self] in
                                self?.updateJob(jobID) { job in
                                    if value < 0.2 {
                                        job.phase = .encoding
                                        job.progress = value * 0.45
                                    } else if value < 0.9 {
                                        job.phase = .uploading
                                        job.progress = 0.2 + (value - 0.2) * 0.65
                                    } else {
                                        job.phase = .publishing
                                        job.progress = 0.85 + (value - 0.9) * 1.5
                                    }
                                }
                            }
                        }
                    )
                }
            }

            services.detailCache.seed(reel)
            OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
            cleanupReelFiles(draft)
            MediaVideoPreparation.cleanupTemporaryFile(at: draft.localVideoURL)
            await completeJob(jobID: jobID, kind: .reel, runGeneration: runGeneration)
        } catch {
            await failJob(jobID: jobID, error: error, runGeneration: runGeneration)
        }
        await UploadProgressRelay.shared.unregister(jobID: jobID)
    }

    private func runPost(
        jobID: String,
        spec: PostUploadSpec,
        services: GlobalUploadServices,
        checkpoint: PostUploadCheckpoint,
        runGeneration: UInt64
    ) async {
        guard jobRunIsLive(jobID: jobID, generation: runGeneration, stage: "runPost.entry") else { return }
        var checkpoint = checkpoint
        await registerProgress(jobID: jobID, phase: .uploading) { [weak self] fraction in
            self?.updateJob(jobID) { job in
                job.phase = .uploading
                job.progress = 0.15 + fraction * 0.7
            }
        }

        do {
            updateJob(jobID) { $0.phase = .preparing }
            let content = spec.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            let post: Post
            if spec.authorID.rawValue.hasPrefix("dev.") {
                var fixture = CreatePostFixtures.samplePost(author: spec.authorID, body: content)
                if spec.imageData != nil {
                    fixture.media = [MediaReference(id: "dev/create-post.jpg", kind: .image, altText: nil)]
                }
                post = fixture
            } else {
                var imageURL = checkpoint.uploadedImagePublicURL
                if imageURL == nil, let imageData = spec.imageData {
                    updateJob(jobID) { $0.phase = .uploading; $0.progress = 0.05 }
                    let path = checkpoint.imageStoragePath
                        ?? "\(spec.authorID.rawValue)/\(jobID).jpg"
                    checkpoint.imageStoragePath = path
                    persistPostRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                    let ref = try await UploadProgressContext.$jobID.withValue(jobID) {
                        try await services.uploadService.upload(
                            UploadRequest(
                                bucket: StorageBucket.profilePosts.rawValue,
                                path: path,
                                data: imageData,
                                contentType: "image/jpeg",
                                purpose: .postImage,
                                cacheControl: StorageCacheControl.immutableMaxAge
                            )
                        )
                    }
                    imageURL = services.objectStorage.publicURL(
                        bucket: StorageBucket.profilePosts.rawValue,
                        path: ref.id
                    )?.absoluteString ?? ref.id
                    checkpoint.uploadedImagePublicURL = imageURL
                    persistPostRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                    GlobalUploadJobDiagnostics.log(
                        id: jobID,
                        kind: .post,
                        event: .storageCompleted,
                        taskCancelled: Task.isCancelled
                    )
                }
                updateJob(jobID) { $0.phase = .publishing; $0.progress = 0.9 }
                guard let profiles = services.profiles else {
                    throw AppError.unknown(message: "Profiles service unavailable.")
                }
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .post,
                    event: .publishStarted,
                    taskCancelled: Task.isCancelled
                )
                GlobalUploadJobDiagnostics.logPublishRequest(
                    jobID: jobID,
                    kind: .post,
                    owner: "GlobalUploadCoordinator"
                )
                post = try await profiles.createWallPost(
                    authorID: spec.authorID,
                    content: content,
                    imageURL: imageURL,
                    imageCrop: nil
                )
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .post,
                    event: .publishCompleted,
                    taskCancelled: Task.isCancelled
                )
            }
            OwnerProfileOptimisticStore.shared.notePostCreated(post)
            await completeJob(jobID: jobID, kind: .post, runGeneration: runGeneration)
        } catch {
            persistPostRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            if Task.isCancelled || error is CancellationError {
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .post,
                    event: .cancelled,
                    taskCancelled: true,
                    cancelSource: "runPost",
                    detail: String(describing: error)
                )
            } else {
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .post,
                    event: .failed,
                    taskCancelled: Task.isCancelled,
                    detail: String(describing: error)
                )
            }
            await failJob(jobID: jobID, error: error, runGeneration: runGeneration)
        }
        await UploadProgressRelay.shared.unregister(jobID: jobID)
    }

    private func runStory(
        jobID: String,
        spec: StoryUploadSpec,
        services: GlobalUploadServices,
        runGeneration: UInt64
    ) async {
        guard jobRunIsLive(jobID: jobID, generation: runGeneration, stage: "runStory.entry") else { return }
        await registerProgress(jobID: jobID, phase: .uploading) { [weak self] fraction in
            self?.updateJob(jobID) { job in
                job.phase = .uploading
                job.progress = 0.1 + fraction * 0.75
            }
        }

        do {
            updateJob(jobID) { $0.phase = .preparing }
            let story: Story
            if spec.authorID.rawValue.hasPrefix("dev.") {
                story = Story(
                    id: StoryID("dev-story-\(UUID().uuidString.prefix(8))"),
                    authorProfileID: spec.authorID,
                    media: MediaReference(id: "dev/story-preview.jpg", kind: .image, altText: nil),
                    expiresAt: Date().addingTimeInterval(ActiveStorySemantics.window),
                    createdAt: Date(),
                    viewerHasSeen: false
                )
            } else {
                story = try await UploadProgressContext.$jobID.withValue(jobID) {
                    try await StoryPublishPipeline.publish(
                        imageData: spec.imageData,
                        contentType: spec.contentType,
                        originalFileName: spec.originalFileName ?? "story.jpg",
                        authorID: spec.authorID,
                        feed: services.feed,
                        uploadService: services.uploadService,
                        objectStorage: services.objectStorage,
                        predeterminedStoragePath: spec.storagePath
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.updateJob(jobID) { job in
                                if progress < 0.85 {
                                    job.phase = .uploading
                                    job.progress = 0.1 + progress * 0.75
                                } else {
                                    job.phase = .publishing
                                    job.progress = 0.85 + (progress - 0.85) * 1.0
                                }
                            }
                        }
                    }
                }
            }
            services.detailCache.seed(story)
            ContentMutationStore.shared.noteStoryCreated(story)
            storySuccessHandlers[jobID]?(story)
            storySuccessHandlers.removeValue(forKey: jobID)
            await completeJob(jobID: jobID, kind: .story, runGeneration: runGeneration)
        } catch {
            await failJob(jobID: jobID, error: error, runGeneration: runGeneration)
        }
        await UploadProgressRelay.shared.unregister(jobID: jobID)
    }

    private func runAchievement(
        jobID: String,
        spec: AchievementUploadSpec,
        services: GlobalUploadServices,
        checkpoint: AchievementUploadCheckpoint,
        runGeneration: UInt64
    ) async {
        guard jobRunIsLive(jobID: jobID, generation: runGeneration, stage: "runAchievement.entry") else { return }
        var checkpoint = checkpoint
        await registerProgress(jobID: jobID, phase: .uploading) { [weak self] fraction in
            self?.updateJob(jobID) { job in
                job.phase = .uploading
                job.progress = fraction * 0.85
            }
        }

        do {
            if checkpoint.savedAchievementID != nil {
                await completeJob(jobID: jobID, kind: .achievement, runGeneration: runGeneration)
                await UploadProgressRelay.shared.unregister(jobID: jobID)
                return
            }

            updateJob(jobID) { $0.phase = .preparing }
            guard let achievements = services.achievements else {
                throw AppError.unknown(message: "Achievements service unavailable.")
            }

            let imageRef: MediaReference
            if spec.authorID.rawValue.hasPrefix("dev.") {
                imageRef = MediaReference(id: "dev/create-achievement.jpg", kind: .image, altText: nil)
            } else if let publicURL = checkpoint.uploadedImagePublicURL {
                imageRef = MediaReference(id: publicURL, kind: .image, altText: nil)
            } else {
                updateJob(jobID) { $0.phase = .uploading; $0.progress = 0.05 }
                let path = "achievements/\(spec.authorID.rawValue)/\(spec.jobID).jpg"
                let reference = try await UploadProgressContext.$jobID.withValue(jobID) {
                    try await services.uploadService.upload(
                        UploadRequest(
                            bucket: StorageBucket.screenshots.rawValue,
                            path: path,
                            data: spec.imageData,
                            contentType: "image/jpeg",
                            purpose: .postImage
                        )
                    )
                }
                let publicURL = services.objectStorage.publicURL(
                    bucket: StorageBucket.screenshots.rawValue,
                    path: reference.id
                )?.absoluteString ?? reference.id
                checkpoint.uploadedImageStoragePath = reference.id
                checkpoint.uploadedImagePublicURL = publicURL
                persistAchievementRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                imageRef = MediaReference(id: publicURL, kind: .image, altText: nil)
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .achievement,
                    event: .storageCompleted,
                    taskCancelled: Task.isCancelled
                )
            }

            updateJob(jobID) { $0.phase = .publishing; $0.progress = nil }
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: .achievement,
                event: .publishStarted,
                taskCancelled: Task.isCancelled
            )
            GlobalUploadJobDiagnostics.logPublishRequest(
                jobID: jobID,
                kind: .achievement,
                owner: "GlobalUploadCoordinator"
            )

            let draft = Achievement(
                id: AchievementID("pending"),
                ownerProfileID: spec.authorID,
                kind: spec.kind,
                title: spec.title,
                description: spec.description,
                tier: .bronze,
                value: spec.payout.map { Money(amount: $0) },
                valueText: spec.payoutText,
                firm: spec.firm,
                accountID: spec.accountID,
                image: imageRef,
                isPublic: spec.isPublic,
                isFeatured: false,
                sortOrder: 0,
                achievedAt: spec.achievedAt
            )

            let saved: Achievement
            if spec.authorID.rawValue.hasPrefix("dev.") {
                var fixture = CreateAchievementFixtures.sampleAchievement(
                    owner: spec.authorID,
                    kind: spec.kind,
                    title: spec.title
                )
                fixture.description = draft.description
                fixture.value = draft.value
                fixture.valueText = draft.valueText
                fixture.firm = draft.firm
                fixture.accountID = draft.accountID
                fixture.image = draft.image
                fixture.isPublic = draft.isPublic
                fixture.achievedAt = draft.achievedAt
                saved = fixture
            } else {
                saved = try await achievements.save(draft)
                checkpoint.savedAchievementID = saved.id
                persistAchievementRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                AchievementUploadDiagnostics.logDatabaseCreated(achievementID: saved.id.rawValue)
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .achievement,
                    event: .publishCompleted,
                    taskCancelled: Task.isCancelled
                )
            }

            OwnerProfileOptimisticStore.shared.noteAchievementCreated(saved)
            ExperienceHaptics.play(.achievement)
            await completeJob(jobID: jobID, kind: .achievement, runGeneration: runGeneration)
        } catch {
            persistAchievementRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            await failJob(jobID: jobID, error: error, runGeneration: runGeneration)
        }
        await UploadProgressRelay.shared.unregister(jobID: jobID)
    }

    private func runTrade(
        jobID: String,
        spec: TradeSaveUploadSpec,
        services: GlobalUploadServices,
        checkpoint: TradeSaveUploadCheckpoint,
        runGeneration: UInt64
    ) async {
        guard jobRunIsLive(jobID: jobID, generation: runGeneration, stage: "runTrade.entry") else { return }
        var checkpoint = checkpoint
        var reelDraftForCleanup: ReelDraft?

        do {
            if checkpoint.savedTradeID != nil, !needsTradeClipWork(spec: spec, checkpoint: checkpoint) {
                if jobs.first(where: { $0.id == jobID })?.phase != .completed,
                   completedGenerations[jobID] != runGeneration
                {
                    if let cachedTrade = services.detailCache.trade(id: checkpoint.savedTradeID!) {
                        await finalizeSuccessfulTradeUpload(
                            jobID: jobID,
                            spec: spec,
                            trade: cachedTrade,
                            checkpoint: checkpoint,
                            runGeneration: runGeneration,
                            reelDraftForCleanup: nil
                        )
                    } else if let trades = services.trades,
                              let loaded = try? await trades.trade(id: checkpoint.savedTradeID!)
                    {
                        await finalizeSuccessfulTradeUpload(
                            jobID: jobID,
                            spec: spec,
                            trade: loaded,
                            checkpoint: checkpoint,
                            runGeneration: runGeneration,
                            reelDraftForCleanup: nil
                        )
                    }
                }
                await UploadProgressRelay.shared.unregister(jobID: jobID)
                return
            }

            updateJob(jobID) { $0.phase = .preparing }
            guard let trades = services.trades else {
                throw AppError.unknown(message: "Trades service unavailable.")
            }

            var resolvedReel: ReelEncodingPipeline.ResolvedUploadVideo?
            if let snapshot = spec.reelSnapshot,
               checkpoint.reelVideoPublicURL == nil,
               !spec.authorID.rawValue.hasPrefix("dev.")
            {
                updateJob(jobID) { job in
                    job.phase = .encoding
                    job.progress = nil
                }
                let draft = snapshot.asDraft
                reelDraftForCleanup = draft
                resolvedReel = try await ReelEncodingPipeline.resolveUploadVideo(draft: draft) { value in
                    Task { @MainActor [weak self] in
                        self?.updateJob(jobID) { job in
                            job.phase = .encoding
                            job.progress = value * 0.2
                        }
                    }
                }
            }

            let screenshotBytes = Int64(spec.screenshotData?.count ?? 0)
            let videoBytes: Int64 = {
                if checkpoint.reelVideoPublicURL != nil { return 0 }
                if let resolvedReel {
                    return Int64((try? Data(contentsOf: resolvedReel.fileURL).count) ?? tradeUploadByteEstimate(spec))
                }
                return 0
            }()
            let thumbBytes: Int64 = {
                if checkpoint.reelVideoPublicURL != nil { return 0 }
                return Int64(spec.reelSnapshot?.thumbnailJPEG?.count ?? 0)
            }()
            let aggregateTotal = max(1, screenshotBytes + videoBytes + thumbBytes)

            if screenshotBytes + videoBytes + thumbBytes > 0 {
                await UploadProgressRelay.shared.configureAggregate(
                    jobID: jobID,
                    totalBytes: aggregateTotal
                ) { fraction in
                    Task { @MainActor [weak self] in
                        self?.updateJob(jobID) { job in
                            job.phase = .uploading
                            job.progress = min(0.85, fraction * 0.85)
                        }
                    }
                }
                if screenshotBytes > 0, checkpoint.uploadedScreenshotPublicURL == nil {
                    await UploadProgressRelay.shared.registerSegment(
                        jobID: jobID,
                        segmentID: "screenshot",
                        byteCount: screenshotBytes
                    )
                }
                if videoBytes > 0 {
                    await UploadProgressRelay.shared.registerSegment(
                        jobID: jobID,
                        segmentID: "reelVideo",
                        byteCount: videoBytes
                    )
                }
                if thumbBytes > 0 {
                    await UploadProgressRelay.shared.registerSegment(
                        jobID: jobID,
                        segmentID: "reelThumb",
                        byteCount: thumbBytes
                    )
                }
            } else {
                await registerProgress(jobID: jobID, phase: .uploading) { [weak self] fraction in
                    self?.updateJob(jobID) { job in
                        job.phase = .uploading
                        job.progress = fraction * 0.85
                    }
                }
            }

            var imageURL = checkpoint.uploadedScreenshotPublicURL ?? spec.existingImageURL
            if checkpoint.uploadedScreenshotPublicURL == nil,
               let screenshotData = spec.screenshotData
            {
                await UploadProgressRelay.shared.setActiveSegment(jobID: jobID, segmentID: "screenshot")
                let path = checkpoint.uploadedScreenshotStoragePath
                    ?? "\(spec.authorID.rawValue)/\(spec.jobID).jpg"
                checkpoint.uploadedScreenshotStoragePath = path
                persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                let reference = try await UploadProgressContext.$jobID.withValue(jobID) {
                    try await services.uploadService.upload(
                        UploadRequest(
                            bucket: StorageBucket.screenshots.rawValue,
                            path: path,
                            data: screenshotData,
                            contentType: "image/jpeg",
                            purpose: .tradeScreenshot
                        )
                    )
                }
                let publicURL = services.objectStorage.publicURL(
                    bucket: StorageBucket.screenshots.rawValue,
                    path: reference.id
                )?.absoluteString ?? reference.id
                checkpoint.uploadedScreenshotStoragePath = reference.id
                checkpoint.uploadedScreenshotPublicURL = publicURL
                imageURL = publicURL
                persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                TradeUploadDiagnostics.log(
                    jobID: jobID,
                    stage: "storageCompleted",
                    progress: 0.85
                )
            } else if spec.removeExistingScreenshot {
                imageURL = nil
            }

            if let resolvedReel, checkpoint.reelVideoPublicURL == nil, let snapshot = spec.reelSnapshot {
                let videoData = try Data(contentsOf: resolvedReel.fileURL, options: [.mappedIfSafe])
                guard videoData.count <= MediaVideoPreparation.maxFinalUploadBytes else {
                    throw AppError.unknown(message: "Videos must be 100 MB or smaller.")
                }
                let videoPath = checkpoint.reelVideoStoragePath
                    ?? "\(spec.authorID.rawValue)/videos/\(spec.jobID)-clip.mp4"
                checkpoint.reelVideoStoragePath = videoPath
                persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                await UploadProgressRelay.shared.setActiveSegment(jobID: jobID, segmentID: "reelVideo")
                let videoRef = try await UploadProgressContext.$jobID.withValue(jobID) {
                    try await services.uploadService.upload(
                        UploadRequest(
                            bucket: StorageBucket.reels.rawValue,
                            path: videoPath,
                            data: videoData,
                            contentType: "video/mp4",
                            purpose: nil,
                            cacheControl: "31536000"
                        )
                    )
                }
                let videoPublic = services.objectStorage.publicURL(
                    bucket: StorageBucket.reels.rawValue,
                    path: videoRef.id
                )?.absoluteString ?? videoRef.id
                checkpoint.reelVideoStoragePath = videoRef.id
                checkpoint.reelVideoPublicURL = videoPublic

                if let jpeg = snapshot.thumbnailJPEG {
                    let thumbPath = checkpoint.reelThumbnailStoragePath
                        ?? "\(spec.authorID.rawValue)/thumbnails/\(spec.jobID)-thumb.jpg"
                    checkpoint.reelThumbnailStoragePath = thumbPath
                    persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                    await UploadProgressRelay.shared.setActiveSegment(jobID: jobID, segmentID: "reelThumb")
                    let thumbRef = try await UploadProgressContext.$jobID.withValue(jobID) {
                        try await services.uploadService.upload(
                            UploadRequest(
                                bucket: StorageBucket.reels.rawValue,
                                path: thumbPath,
                                data: jpeg,
                                contentType: "image/jpeg",
                                purpose: .reelThumbnail
                            )
                        )
                    }
                    let thumbPublic = services.objectStorage.publicURL(
                        bucket: StorageBucket.reels.rawValue,
                        path: thumbRef.id
                    )?.absoluteString ?? thumbRef.id
                    checkpoint.reelThumbnailStoragePath = thumbRef.id
                    checkpoint.reelThumbnailPublicURL = thumbPublic
                }
                persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                ReelEncodingPipeline.cleanupEphemeralFiles(
                    resolvedReel.ephemeralURLs,
                    preserving: Set([snapshot.localVideoURL, snapshot.ownedSourceURL].compactMap { $0 })
                )
            }

            guard jobRunMayFinalize(jobID: jobID, generation: runGeneration, stage: "runTrade.prePublish") else {
                return
            }

            let socialPostRequested = spec.draft.visibility == .public
            updateJobProgress(jobID: jobID, phase: .publishing, progress: 0.88)

            var draft = spec.draft
            draft.imageURL = imageURL

            var editPreviousTrade: Trade?
            let trade: Trade
            if spec.authorID.rawValue.hasPrefix("dev.") {
                switch spec.mode {
                case .create:
                    trade = AddTradeViewModel.devFixtureTrade(from: draft, owner: spec.authorID)
                case .edit(let tradeID):
                    let previous = services.detailCache.trade(id: tradeID)
                        ?? AddTradeViewModel.devFixtureTrade(from: draft, owner: spec.authorID)
                    trade = AddTradeViewModel.devFixtureUpdatedTrade(from: draft, previous: previous)
                }
                checkpoint.savedTradeID = trade.id
                checkpoint.publicFeedPostCompleted = socialPostRequested
            } else if let savedID = checkpoint.savedTradeID {
                var loaded = try await trades.trade(id: savedID)
                if socialPostRequested, !checkpoint.publicFeedPostCompleted {
                    loaded = try await trades.update(id: savedID, draft: draft, previous: loaded)
                    checkpoint.publicFeedPostCompleted = true
                    persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                    TradeUploadDiagnostics.log(
                        jobID: jobID,
                        stage: "socialPostCreated",
                        tradeID: loaded.id.rawValue,
                        socialPostRequested: true,
                        progress: 0.94
                    )
                }
                trade = loaded
            } else {
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: .trade,
                    event: .publishStarted,
                    taskCancelled: Task.isCancelled
                )
                GlobalUploadJobDiagnostics.logPublishRequest(
                    jobID: jobID,
                    kind: .trade,
                    owner: "GlobalUploadCoordinator"
                )
                if case .edit(let tradeID) = spec.mode {
                    let previous: Trade
                    if let cached = services.detailCache.trade(id: tradeID) {
                        previous = cached
                    } else {
                        previous = try await trades.trade(id: tradeID)
                    }
                    editPreviousTrade = previous
                    trade = try await trades.update(id: tradeID, draft: draft, previous: previous)
                    checkpoint.savedTradeID = trade.id
                    checkpoint.publicFeedPostCompleted = socialPostRequested
                    persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                } else {
                    trade = try await trades.save(draft)
                    checkpoint.savedTradeID = trade.id
                    checkpoint.publicFeedPostCompleted = socialPostRequested
                    persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
                }
                TradeUploadDiagnostics.log(
                    jobID: jobID,
                    stage: "tradeCreated",
                    tradeID: trade.id.rawValue,
                    socialPostRequested: socialPostRequested,
                    progress: 0.92
                )
                if socialPostRequested {
                    TradeUploadDiagnostics.log(
                        jobID: jobID,
                        stage: "socialPostCreated",
                        tradeID: trade.id.rawValue,
                        socialPostRequested: true,
                        socialPostID: trade.id.rawValue,
                        progress: 0.94
                    )
                }
            }

            guard jobRunMayFinalize(jobID: jobID, generation: runGeneration, stage: "runTrade.postPersist") else {
                await finishTradeJobIfPersisted(
                    jobID: jobID,
                    spec: spec,
                    services: services,
                    checkpoint: checkpoint,
                    trade: trade,
                    runGeneration: runGeneration,
                    reelDraftForCleanup: reelDraftForCleanup
                )
                return
            }

            reconcileTradeAfterSave(trade, mode: spec.mode, previous: editPreviousTrade)
            if let accountID = spec.lastAccountID {
                AddTradeViewModel.rememberLastAccountID(accountID)
            }
            TradeUploadDiagnostics.log(
                jobID: jobID,
                stage: "reconciled",
                tradeID: trade.id.rawValue,
                socialPostRequested: socialPostRequested,
                progress: 0.96
            )
            updateJobProgress(jobID: jobID, phase: .publishing, progress: 0.96)

            if needsTradeClipWork(spec: spec, checkpoint: checkpoint) {
                try await attachTradeClipForUpload(
                    jobID: jobID,
                    spec: spec,
                    services: services,
                    trade: trade,
                    checkpoint: &checkpoint
                )
            } else if !checkpoint.clipAttached, spec.reelSnapshot == nil, spec.linkedReelID == nil {
                checkpoint.clipAttached = true
                persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            }

            guard jobRunMayFinalize(jobID: jobID, generation: runGeneration, stage: "runTrade.preComplete") else {
                await finishTradeJobIfPersisted(
                    jobID: jobID,
                    spec: spec,
                    services: services,
                    checkpoint: checkpoint,
                    trade: trade,
                    runGeneration: runGeneration,
                    reelDraftForCleanup: reelDraftForCleanup
                )
                return
            }

            guard !needsTradeClipWork(spec: spec, checkpoint: checkpoint) else {
                throw AppError.unknown(message: "Trade clip linking did not finish.")
            }

            await finalizeSuccessfulTradeUpload(
                jobID: jobID,
                spec: spec,
                trade: trade,
                checkpoint: checkpoint,
                runGeneration: runGeneration,
                reelDraftForCleanup: reelDraftForCleanup
            )
        } catch {
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            await failJob(jobID: jobID, error: error, runGeneration: runGeneration)
        }
        await UploadProgressRelay.shared.unregister(jobID: jobID)
    }

    private func persistPostRetry(
        jobID: String,
        spec: PostUploadSpec,
        services: GlobalUploadServices,
        checkpoint: PostUploadCheckpoint
    ) {
        retryPost[jobID] = (spec, services, checkpoint)
    }

    private func persistAchievementRetry(
        jobID: String,
        spec: AchievementUploadSpec,
        services: GlobalUploadServices,
        checkpoint: AchievementUploadCheckpoint
    ) {
        retryAchievement[jobID] = (spec, services, checkpoint)
    }

    private func persistTradeRetry(
        jobID: String,
        spec: TradeSaveUploadSpec,
        services: GlobalUploadServices,
        checkpoint: TradeSaveUploadCheckpoint
    ) {
        retryTrade[jobID] = (spec, services, checkpoint)
    }

    private func attachTradeClipForUpload(
        jobID: String,
        spec: TradeSaveUploadSpec,
        services: GlobalUploadServices,
        trade: Trade,
        checkpoint: inout TradeSaveUploadCheckpoint
    ) async throws {
        if spec.authorID.rawValue.hasPrefix("dev.") {
            if spec.reelSnapshot != nil {
                let reel = CreateReelFixtures.sampleReel(author: spec.authorID, tradeID: trade.id)
                services.detailCache.seed(reel)
                OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
            } else if let linked = spec.linkedReelID {
                checkpoint.reelLinked = true
                checkpoint.linkedExistingReelID = linked
                ContentMutationStore.shared.noteReelLinked(linked)
            }
            checkpoint.clipAttached = true
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            return
        }

        if let linkedID = spec.linkedReelID {
            try await linkSelectedReelToTrade(
                jobID: jobID,
                reelID: linkedID,
                trade: trade,
                spec: spec,
                services: services,
                checkpoint: &checkpoint
            )
            return
        }

        if spec.reelSnapshot == nil {
            checkpoint.clipAttached = true
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            return
        }

        if try await services.feed.tradeHasAttachedReel(trade.id) {
            checkpoint.clipAttached = true
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            return
        }

        guard checkpoint.reelVideoPublicURL != nil else {
            checkpoint.clipAttached = true
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            return
        }

        let snapshot = spec.reelSnapshot
        let videoURL = checkpoint.reelVideoPublicURL!
        let thumbURL = checkpoint.reelThumbnailPublicURL ?? videoURL
        let visibility: ContentVisibility = spec.tradeIsPublic ? .public : .private
        let provisional = Reel(
            id: ReelID(UUID().uuidString),
            authorProfileID: spec.authorID,
            video: MediaReference(id: videoURL, kind: .video, altText: nil),
            thumbnail: MediaReference(id: thumbURL, kind: .image, altText: nil),
            caption: nil,
            visibility: visibility,
            linkedTradeID: trade.id,
            durationSeconds: snapshot?.durationSeconds ?? 0,
            createdAt: .now
        )
        let inserted = try await services.feed.createReel(provisional)
        let verified = try await services.feed.reel(id: inserted.id)
        guard verified.reel.authorProfileID == spec.authorID else {
            throw AppError.unknown(message: "Published clip could not be verified.")
        }
        services.detailCache.seed(verified.reel)
        OwnerProfileOptimisticStore.shared.noteReelCreated(verified.reel)
        checkpoint.clipAttached = true
        persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
        TradeUploadDiagnostics.log(
            jobID: jobID,
            stage: "clipAttached",
            tradeID: trade.id.rawValue,
            reelSelected: false,
            reelLinked: false,
            progress: 0.98
        )
    }

    private func linkSelectedReelToTrade(
        jobID: String,
        reelID: ReelID,
        trade: Trade,
        spec: TradeSaveUploadSpec,
        services: GlobalUploadServices,
        checkpoint: inout TradeSaveUploadCheckpoint
    ) async throws {
        let tradeID = trade.id.rawValue
        let reelIDRaw = reelID.rawValue

        if checkpoint.reelLinked, checkpoint.linkedExistingReelID == reelID {
            checkpoint.clipAttached = true
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            return
        }

        TradeReelLinkDiagnostics.log(
            jobID: jobID,
            tradeID: tradeID,
            reelID: reelIDRaw,
            stage: "started"
        )
        updateJobProgress(jobID: jobID, phase: .publishing, progress: 0.97)

        do {
            TradeReelLinkDiagnostics.log(
                jobID: jobID,
                tradeID: tradeID,
                reelID: reelIDRaw,
                stage: "requestStarted"
            )
            try await services.feed.linkReelToTrade(
                reelID: reelID,
                tradeID: trade.id,
                ownerID: spec.authorID,
                tradeIsPublic: spec.tradeIsPublic,
                linkJobID: jobID
            )
            checkpoint.reelLinked = true
            checkpoint.linkedExistingReelID = reelID
            checkpoint.clipAttached = true
            ContentMutationStore.shared.noteReelLinked(reelID)
            persistTradeRetry(jobID: jobID, spec: spec, services: services, checkpoint: checkpoint)
            TradeReelLinkDiagnostics.log(
                jobID: jobID,
                tradeID: tradeID,
                reelID: reelIDRaw,
                stage: "succeeded"
            )
            TradeUploadDiagnostics.log(
                jobID: jobID,
                stage: "reelLinked",
                tradeID: tradeID,
                reelSelected: true,
                reelLinked: true,
                progress: 0.98
            )
        } catch {
            TradeReelLinkDiagnostics.log(
                jobID: jobID,
                tradeID: tradeID,
                reelID: reelIDRaw,
                stage: "failed",
                error: TradeReelLinkDiagnostics.failureDetail(for: error)
            )
            throw error
        }
    }

    private func finalizeSuccessfulTradeUpload(
        jobID: String,
        spec: TradeSaveUploadSpec,
        trade: Trade,
        checkpoint: TradeSaveUploadCheckpoint,
        runGeneration: UInt64,
        reelDraftForCleanup: ReelDraft?
    ) async {
        guard jobRunMayFinalize(jobID: jobID, generation: runGeneration, stage: "finalizeSuccessfulTradeUpload") else {
            return
        }
        let reelSelected = spec.linkedReelID != nil
        TradeUploadDiagnostics.log(
            jobID: jobID,
            stage: "publishCompleted",
            tradeID: trade.id.rawValue,
            socialPostRequested: spec.draft.visibility == .public,
            reelSelected: reelSelected,
            reelLinked: checkpoint.reelLinked,
            progress: 1.0
        )
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: .trade,
            event: .publishCompleted,
            taskCancelled: Task.isCancelled,
            generation: runGeneration
        )
        ExperienceHaptics.play(.tradeSaved)
        if case .create = spec.mode {
            PostTradeReflectionGate.shared.present(trade)
        }
        if let draft = reelDraftForCleanup {
            cleanupReelFiles(draft)
        }
        await completeJob(jobID: jobID, kind: .trade, runGeneration: runGeneration)
    }

    private func tradeUploadByteEstimate(_ spec: TradeSaveUploadSpec) -> Int {
        spec.reelSnapshot?.byteCount ?? 0
    }

    // MARK: - Helpers

    private func startTask(
        jobID: String,
        kind: UploadJobKind,
        intent: StartIntent,
        operation: @escaping @MainActor (UInt64) async -> Void
    ) {
        if terminalJobIDs.contains(jobID) {
            #if DEBUG
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: kind,
                event: .staleRunIgnored,
                taskCancelled: false,
                generation: completedGenerations[jobID],
                detail: "startBlockedTerminalJob"
            )
            #endif
            return
        }
        if intent == .enqueue {
            if completedGenerations[jobID] != nil {
                #if DEBUG
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: kind,
                    event: .staleRunIgnored,
                    taskCancelled: false,
                    generation: completedGenerations[jobID],
                    detail: "startBlockedCompletedTerminal"
                )
                #endif
                return
            }
            if let job = jobs.first(where: { $0.id == jobID }), job.phase == .completed {
                #if DEBUG
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: kind,
                    event: .staleRunIgnored,
                    taskCancelled: false,
                    generation: jobRunGeneration[jobID],
                    detail: "startBlockedJobPhaseCompleted"
                )
                #endif
                return
            }
            if tasks[jobID] != nil {
                #if DEBUG
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: kind,
                    event: .staleRunIgnored,
                    taskCancelled: false,
                    generation: activeTaskGenerations[jobID],
                    detail: "startBlockedAlreadyRunning"
                )
                #endif
                return
            }
        }

        if intent == .retry {
            scheduledRemovalTasks[jobID]?.cancel()
            scheduledRemovalTasks.removeValue(forKey: jobID)
            if tasks[jobID] != nil {
                GlobalUploadJobDiagnostics.log(
                    id: jobID,
                    kind: kind,
                    event: .cancelled,
                    taskCancelled: tasks[jobID]?.isCancelled ?? false,
                    generation: activeTaskGenerations[jobID],
                    cancelSource: "startTask:retryReplace"
                )
                tasks[jobID]?.cancel()
                tasks.removeValue(forKey: jobID)
                activeTaskGenerations.removeValue(forKey: jobID)
            }
        }

        let generation = (jobRunGeneration[jobID] ?? 0) + 1
        jobRunGeneration[jobID] = generation
        activeTaskGenerations[jobID] = generation
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: kind,
            event: .started,
            taskCancelled: false,
            generation: generation
        )
        tasks[jobID] = Task.detached(priority: .userInitiated) { @MainActor [weak self] in
            await operation(generation)
            guard let self else { return }
            if self.activeTaskGenerations[jobID] == generation {
                self.activeTaskGenerations.removeValue(forKey: jobID)
            }
            if self.tasks[jobID]?.isCancelled != true {
                self.tasks.removeValue(forKey: jobID)
            }
        }
    }

    private func registerProgress(
        jobID: String,
        phase: UploadJobPhase,
        handler: @escaping @MainActor (Double) -> Void
    ) async {
        await UploadProgressRelay.shared.register(jobID: jobID) { fraction in
            Task { @MainActor in handler(fraction) }
        }
        updateJob(jobID) { job in
            job.phase = phase
        }
    }

    private func completeJob(jobID: String, kind: UploadJobKind, runGeneration: UInt64) async {
        guard jobRunMayFinalize(jobID: jobID, generation: runGeneration, stage: "completeJob") else { return }
        if completedGenerations[jobID] == runGeneration {
            return
        }
        completedGenerations[jobID] = runGeneration
        activeTaskGenerations.removeValue(forKey: jobID)
        updateJob(jobID) { job in
            job.phase = .completed
            job.progress = 1
            job.completedAt = Date()
            job.showsSuccessFlash = true
            job.title = kind.defaultTitle
        }
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: kind,
            event: .completed,
            taskCancelled: Task.isCancelled,
            generation: runGeneration
        )
        ExperienceHaptics.play(.success)
        scheduledRemovalTasks[jobID]?.cancel()
        scheduledRemovalTasks[jobID] = Task.detached { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            guard self.completedGenerations[jobID] == runGeneration else { return }
            guard self.jobRunGeneration[jobID] == runGeneration else { return }
            self.finalizeCompletedJob(jobID: jobID, runGeneration: runGeneration, kind: kind)
        }
    }

    private func failJob(jobID: String, error: Error, runGeneration: UInt64) async {
        guard jobRunIsLive(jobID: jobID, generation: runGeneration, stage: "failJob") else { return }
        let message = ProfileSectionSupport.message(for: error)
        updateJob(jobID) { job in
            job.phase = .failed
            job.errorMessage = message
        }
    }

    private func invalidateJobRun(jobID: String) {
        jobRunGeneration[jobID] = (jobRunGeneration[jobID] ?? 0) + 1
    }

    private func clearRetryState(jobID: String) {
        retryReel.removeValue(forKey: jobID)
        retryPost.removeValue(forKey: jobID)
        retryStory.removeValue(forKey: jobID)
        retryAchievement.removeValue(forKey: jobID)
        retryTrade.removeValue(forKey: jobID)
        storySuccessHandlers.removeValue(forKey: jobID)
    }

    /// Success-path cleanup — does not cancel the worker task that just finished.
    private func finalizeCompletedJob(jobID: String, runGeneration: UInt64, kind: UploadJobKind) {
        guard completedGenerations[jobID] == runGeneration else { return }
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: kind,
            event: .removed,
            taskCancelled: false,
            generation: runGeneration,
            removalReason: "completedCleanup"
        )
        scheduledRemovalTasks.removeValue(forKey: jobID)
        tasks.removeValue(forKey: jobID)
        activeTaskGenerations.removeValue(forKey: jobID)
        clearRetryState(jobID: jobID)
        jobs.removeAll { $0.id == jobID }
        jobRunGeneration.removeValue(forKey: jobID)
        terminalJobIDs.insert(jobID)
    }

    @discardableResult
    private func jobRunIsLive(jobID: String, generation: UInt64, stage: String) -> Bool {
        let kind = jobs.first(where: { $0.id == jobID })?.kind ?? .trade
        let generationMatches = jobRunGeneration[jobID] == generation
        let jobListed = jobs.contains { $0.id == jobID }
        let terminalCompleted = completedGenerations[jobID] == generation
        let live = generationMatches && jobListed && !Task.isCancelled && !terminalCompleted
        #if DEBUG
        if !live {
            let staleCleanup = terminalCompleted || (!jobListed && completedGenerations[jobID] != nil)
            let event: GlobalUploadJobDiagnostics.Event = staleCleanup || !generationMatches
                ? .staleRunIgnored
                : .cancelled
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: kind,
                event: event,
                taskCancelled: Task.isCancelled,
                generation: generation,
                cancelSource: event == .cancelled ? "jobRunIsLive:\(stage)" : nil,
                detail: "generationMatches=\(generationMatches) jobListed=\(jobListed) terminalCompleted=\(terminalCompleted)"
            )
        }
        #endif
        return live
    }

    /// Post-upload / post-persist — allow finishing UI even if cooperative cancellation was set spuriously.
    @discardableResult
    private func jobRunMayFinalize(jobID: String, generation: UInt64, stage: String) -> Bool {
        let kind = jobs.first(where: { $0.id == jobID })?.kind ?? .trade
        let generationMatches = jobRunGeneration[jobID] == generation
        let jobListed = jobs.contains { $0.id == jobID }
        if completedGenerations[jobID] == generation, jobListed {
            return true
        }
        let ok = generationMatches && jobListed
        #if DEBUG
        if !ok {
            let staleCleanup = completedGenerations[jobID] != nil && completedGenerations[jobID] != generation
            GlobalUploadJobDiagnostics.log(
                id: jobID,
                kind: kind,
                event: staleCleanup || !generationMatches ? .staleRunIgnored : .cancelled,
                taskCancelled: Task.isCancelled,
                generation: generation,
                cancelSource: ok ? nil : "jobRunMayFinalize:\(stage)",
                detail: "generationMatches=\(generationMatches) jobListed=\(jobListed)"
            )
        }
        #endif
        return ok
    }

    private func clampedProgress(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    private func updateJobProgress(jobID: String, phase: UploadJobPhase? = nil, progress: Double?) {
        updateJob(jobID) { job in
            if let phase { job.phase = phase }
            job.progress = clampedProgress(progress)
        }
    }

    private func reconcileTradeAfterSave(
        _ trade: Trade,
        mode: TradeSaveUploadMode,
        previous: Trade? = nil
    ) {
        switch mode {
        case .create:
            TradeJournalMutationStore.shared.noteCreated(trade)
        case .edit:
            TradeJournalMutationStore.shared.noteUpdated(trade, previous: previous)
        }
    }

    private func needsTradeClipWork(spec: TradeSaveUploadSpec, checkpoint: TradeSaveUploadCheckpoint) -> Bool {
        if checkpoint.clipAttached { return false }
        if spec.linkedReelID != nil { return !checkpoint.reelLinked }
        guard spec.reelSnapshot != nil else { return false }
        if spec.authorID.rawValue.hasPrefix("dev.") { return true }
        return checkpoint.reelVideoPublicURL != nil
    }

    private func finishTradeJobIfPersisted(
        jobID: String,
        spec: TradeSaveUploadSpec,
        services: GlobalUploadServices,
        checkpoint: TradeSaveUploadCheckpoint,
        trade: Trade,
        runGeneration: UInt64,
        reelDraftForCleanup: ReelDraft?
    ) async {
        guard checkpoint.savedTradeID != nil else { return }
        guard !needsTradeClipWork(spec: spec, checkpoint: checkpoint) else { return }
        await finalizeSuccessfulTradeUpload(
            jobID: jobID,
            spec: spec,
            trade: trade,
            checkpoint: checkpoint,
            runGeneration: runGeneration,
            reelDraftForCleanup: reelDraftForCleanup
        )
    }

    private func cleanupReelFiles(_ draft: ReelDraft) {
        MediaVideoPreparation.cleanupTemporaryFile(at: draft.localVideoURL)
        if let owned = draft.ownedSourceURL {
            ReelVideoImport.cleanup(url: owned)
        }
        ReelVideoImport.cleanup(selectionID: draft.selectionID)
    }

    private func insertJob(_ job: UploadJob) {
        jobs.removeAll { $0.id == job.id }
        jobs.insert(job, at: 0)
    }

    private func updateJob(_ id: String, mutate: (inout UploadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
        if let progress = jobs[index].progress, !progress.isFinite {
            jobs[index].progress = nil
        } else if let progress = jobs[index].progress {
            jobs[index].progress = min(1, max(0, progress))
        }
    }
}
