import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class FeedStoryViewerViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case unavailable
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var story: Story?
    private(set) var author: Profile?
    private(set) var isOwner = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?
    private(set) var authorIndex = 0
    private(set) var slideIndex = 0
    private(set) var isSendingReply = false
    private(set) var replyErrorMessage: String?
    private(set) var videoTextOverlays: [StoryTextOverlayRecord] = []
    private(set) var videoPixelSize: CGSize = .zero

    let storyID: StoryID
    let entryContext: StoryViewerEntryContext
    let playback: StoryPlaybackController

    private var sequence = StoryViewerContinuation()
    private var viewerID: ProfileID?

    private let feed: any FeedRepository
    private let messages: any MessageRepository
    private let session: any SessionProviding
    private let cache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let engagementStore: EngagementStore?
    private let onDismiss: () -> Void

    init(
        storyID: StoryID,
        entryContext: StoryViewerEntryContext = .feedCarousel,
        feed: any FeedRepository,
        messages: any MessageRepository,
        session: any SessionProviding,
        cache: DetailPresentationCache,
        objectStorage: any ObjectStorageProviding,
        engagementStore: EngagementStore? = nil,
        inboxStore: MessagesInboxStore? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.storyID = storyID
        self.entryContext = entryContext
        self.feed = feed
        self.messages = messages
        self.session = session
        self.cache = cache
        self.engagementStore = engagementStore
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
        self.onDismiss = onDismiss
        self.playback = StoryPlaybackController(storage: objectStorage)
        self.playback.onAdvance = { [weak self] in
            self?.advanceFromPlayback()
        }
        self.playback.onVideoPixelSize = { [weak self] size in
            self?.videoPixelSize = size
        }
        self.playback.onMediaUnavailable = { [weak self] in
            self?.reportMediaUnavailable()
        }
    }

    func reportMediaUnavailable() {
        confirmStoryUnavailable(reason: "mediaLoadFailed")
    }

    func tearDown() {
        playback.stopPlayback()
    }

    var showReplyComposer: Bool {
        phase == .loaded && !isOwner && story != nil
    }

    var isVideoStory: Bool {
        guard let story else { return false }
        return StoryPlaybackController.isVideoStory(story)
    }

    var currentSlides: [Story] {
        sequence.slides(at: authorIndex)
    }

    func loadIfNeeded() async {
        StoryDebug.log(
            "viewer.load",
            "story=\(storyID.rawValue) entry=\(String(describing: entryContext))"
        )
        viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        if let viewerID {
            StoryViewerViewRecords.shared.rebindIfNeeded(viewerID: viewerID)
        }
        await bootstrapCatalogIfNeeded()
        guard phase != .unavailable else { return }
        resolveInitialSlideForOpenedAuthor()
        if !sequence.authorOrder.indices.contains(authorIndex)
            || !sequence.slides(at: authorIndex).indices.contains(slideIndex)
        {
            guard let position = sequence.position(of: storyID) else {
                var catalogCount = 0
                for index in sequence.authorOrder.indices {
                    catalogCount += sequence.slides(at: index).count
                }
                StoryDebug.log(
                    "viewer.positionMissing",
                    "story=\(storyID.rawValue) catalogSlides=\(catalogCount) authors=\(sequence.authorOrder.count)"
                )
                confirmStoryUnavailable(reason: "positionMissing")
                return
            }
            authorIndex = position.authorIndex
            slideIndex = position.slideIndex
        }
        StoryDebug.log(
            "viewer.position",
            "story=\(storyID.rawValue) authorIndex=\(authorIndex) slideIndex=\(slideIndex)"
        )
        await applyCurrentSlide()
    }

    /// Same-device deletes, another device, and refreshes all enter here.
    /// A missing slide moves to the next story, the next author, or closes the viewer.
    func absorbRemovedStory(_ storyID: StoryID) async {
        guard sequence.position(of: storyID) != nil else { return }
        let destination = sequence.remove(
            storyIDs: [storyID],
            viewingAuthorIndex: authorIndex,
            viewingSlideIndex: slideIndex
        )
        cache.removeStory(id: storyID)
        FeedStoriesCatalogStore.shared.removeStory(id: storyID)
        await apply(destination)
    }

    func absorbLatestContentMutation() {
        guard case .storyDeleted(let storyID) = ContentMutationStore.shared.latest else { return }
        Task { await absorbRemovedStory(storyID) }
    }

    /// Drops slides whose 24-hour window has ended while the viewer is open.
    func absorbExpiredStories(now: Date = Date()) async {
        guard !entryContext.retainsExpiredStoriesInSequence else { return }
        let visibleID = story?.id
        StoryDebug.log("viewer.expire.check", "visible=\(visibleID?.rawValue ?? "nil")")
        let destination = sequence.dropInactive(
            viewingAuthorIndex: authorIndex,
            viewingSlideIndex: slideIndex,
            now: now
        )
        if case .showing(let nextAuthor, let nextSlide) = destination,
           nextAuthor == authorIndex,
           nextSlide == slideIndex,
           sequence.slides(at: nextAuthor).indices.contains(nextSlide),
           sequence.slides(at: nextAuthor)[nextSlide].id == visibleID
        {
            return
        }
        await apply(destination)
    }

    /// Confirms the visible story still exists. A network failure leaves the current slide up.
    func revalidateVisibleStory() async {
        guard phase == .loaded else { return }
        await absorbExpiredStories()
        guard phase == .loaded, let current = story, let viewerID else { return }
        guard !FeedSupport.isLocalDevelopmentProfile(viewerID) else { return }
        do {
            let fresh = try await feed.storyForViewer(id: current.id)
            if fresh == nil {
                if ActiveStorySemantics.isActive(createdAt: current.createdAt) {
                    StoryDebug.log(
                        "viewer.revalidate.keep",
                        "story=\(current.id.rawValue) rpcNilWhileActive"
                    )
                } else {
                    StoryDebug.log(
                        "viewer.revalidate.removed",
                        "story=\(current.id.rawValue) active=\(ActiveStorySemantics.isActive(createdAt: current.createdAt))"
                    )
                    await absorbRemovedStory(current.id)
                }
            } else if let fresh,
                      !ActiveStorySemantics.isActive(createdAt: fresh.createdAt),
                      entryContext != .storyArchive,
                      entryContext != .dmReferencedStory
            {
                StoryDebug.log(
                    "viewer.revalidate.expired",
                    "story=\(current.id.rawValue) created=\(fresh.createdAt)"
                )
                await absorbExpiredStories()
            }
        } catch {
            StoryDebug.log(
                "viewer.revalidate.error",
                "story=\(current.id.rawValue) error=\(error.localizedDescription)"
            )
            return
        }
    }

    /// While the viewer is open, expire slides on time and notice deletes from another device.
    func watchStoryLifecycle() async {
        while !Task.isCancelled {
            guard phase == .loaded else {
                if phase == .unavailable { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            await revalidateVisibleStory()
            guard phase == .loaded else {
                if phase == .unavailable { return }
                continue
            }
            let delay = secondsUntilSoonestExpiry()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    func setReplyComposerActive(_ active: Bool) {
        if active {
            playback.pause(.composer)
        } else {
            playback.resume(.composer)
        }
    }

    func setHoldPaused(_ paused: Bool) {
        if paused {
            playback.pause(.hold)
        } else {
            playback.resume(.hold)
        }
    }

    func setBackgroundPaused(_ paused: Bool) {
        if paused {
            playback.pause(.background)
        } else {
            playback.resume(.background)
        }
    }

    func goNextSlide() {
        guard phase == .loaded else { return }
        ExperienceHaptics.play(.selection)
        advanceToNextSlide()
    }

    func goPreviousSlide() {
        guard phase == .loaded else { return }
        ExperienceHaptics.play(.selection)
        advanceToPreviousSlide()
    }

    func goNextAuthor() {
        guard phase == .loaded else { return }
        ExperienceHaptics.play(.selection)
        guard entryContext.allowsCrossAuthorNavigation else {
            dismissViewer()
            return
        }
        guard authorIndex < sequence.authorOrder.count - 1 else {
            dismissViewer()
            return
        }
        authorIndex += 1
        slideIndex = 0
        Task { await applyCurrentSlide() }
    }

    func goPreviousAuthor() {
        guard phase == .loaded else { return }
        ExperienceHaptics.play(.selection)
        guard entryContext.allowsCrossAuthorNavigation else {
            dismissViewer()
            return
        }
        guard authorIndex > 0 else {
            dismissViewer()
            return
        }
        authorIndex -= 1
        slideIndex = 0
        Task { await applyCurrentSlide() }
    }

    func dismissViewer(reason: String = "unspecified") {
        StoryDebug.log(
            "viewer.dismiss",
            "reason=\(reason) story=\(storyID.rawValue) phase=\(String(describing: phase))"
        )
        playback.stopPlayback()
        onDismiss()
    }

    private func confirmStoryUnavailable(reason: String) {
        guard phase != .unavailable else { return }
        StoryDebug.log("viewer.unavailable", "\(reason) story=\(storyID.rawValue)")
        playback.stopPlayback()
        phase = .unavailable
    }

    func clearDeleteError() {
        deleteErrorMessage = nil
    }

    func clearReplyError() {
        replyErrorMessage = nil
    }

    func toggleCurrentStoryLike() async {
        guard showReplyComposer,
              let story,
              let engagementStore
        else { return }
        await engagementStore.toggleLike(on: .story(story.id))
    }

    func deleteStory() async -> Bool {
        guard isOwner, !isDeleting, let currentStory = story else { return false }
        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }

        do {
            if let viewer = viewerID,
               !viewer.rawValue.hasPrefix("dev.")
            {
                try await feed.deleteStory(id: currentStory.id)
            }
            let destination = sequence.remove(
                storyIDs: [currentStory.id],
                viewingAuthorIndex: authorIndex,
                viewingSlideIndex: slideIndex
            )
            cache.removeStory(id: currentStory.id)
            FeedStoriesCatalogStore.shared.removeStory(id: currentStory.id)
            ContentMutationStore.shared.noteStoryDeleted(currentStory.id)
            ExperienceHaptics.play(.success)
            await apply(destination)
            return true
        } catch {
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func sendStoryReply(text: String) async -> Bool {
        guard showReplyComposer,
              !isSendingReply,
              let currentStory = story,
              let authorProfile = author,
              let viewerID
        else { return false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isSendingReply = true
        replyErrorMessage = nil
        defer { isSendingReply = false }

        let encoded = StoryReplyMessageSupport.encode(
            text: trimmed,
            storyID: currentStory.id,
            imageURL: currentStory.media.id,
            ownerID: currentStory.authorProfileID,
            ownerUsername: authorProfile.username
        )

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalDevelopment(authorProfile.id)
        {
            let conversation = ConversationCreationSupport.buildDirectConversation(
                id: ConversationID("dev-dm-\(authorProfile.id.rawValue.replacingOccurrences(of: "dev.", with: ""))"),
                viewerID: viewerID,
                recipient: authorProfile
            )
            let optimistic = Message(
                id: MessageID("temp-\(UUID().uuidString)"),
                conversationID: conversation.id,
                senderProfileID: viewerID,
                kind: .storyReply,
                body: encoded,
                attachments: [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            )
            patchInbox(with: optimistic, conversation: conversation, viewerID: viewerID)
            ExperienceHaptics.play(.messageSent)
            return true
        }

        do {
            let result = try await ConversationCreationCoordinator.shared.openDirectConversation(
                viewerID: viewerID,
                recipient: authorProfile,
                messages: messages,
                detailCache: cache,
                inboxStore: inboxStore
            )
            let optimistic = Message(
                id: MessageID("temp-\(UUID().uuidString)"),
                conversationID: result.conversation.id,
                senderProfileID: viewerID,
                kind: .storyReply,
                body: encoded,
                attachments: [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            )
            let saved = try await messages.send(optimistic)
            patchInbox(with: saved, conversation: result.conversation, viewerID: viewerID)
            ExperienceHaptics.play(.messageSent)
            return true
        } catch ConversationCreationCoordinator.CreationError.blockedRecipient {
            replyErrorMessage = "You can't message this trader."
            ExperienceHaptics.play(.warning)
            return false
        } catch {
            replyErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.error)
            return false
        }
    }

    // MARK: - Private

    private func advanceFromPlayback() {
        advanceToNextSlide()
    }

    private func advanceToNextSlide() {
        playback.stopPlayback()
        let slides = currentSlides
        if slideIndex < slides.count - 1 {
            slideIndex += 1
            Task { await applyCurrentSlide() }
            return
        }
        if entryContext.allowsCrossAuthorNavigation, authorIndex < sequence.authorOrder.count - 1 {
            authorIndex += 1
            slideIndex = 0
            Task { await applyCurrentSlide() }
            return
        }
        dismissViewer()
    }

    private func advanceToPreviousSlide() {
        playback.stopPlayback()
        if slideIndex > 0 {
            slideIndex -= 1
            Task { await applyCurrentSlide() }
            return
        }
        if entryContext.allowsCrossAuthorNavigation, authorIndex > 0 {
            authorIndex -= 1
            let previousSlides = sequence.slides(at: authorIndex)
            slideIndex = max(0, previousSlides.count - 1)
            Task { await applyCurrentSlide() }
            return
        }
        dismissViewer()
    }

    private func bootstrapCatalogIfNeeded() async {
        guard let viewerID = viewerID ?? FeedStoriesCatalogStore.shared.viewerID else {
            dismissViewer(reason: "missingViewerID")
            return
        }
        self.viewerID = viewerID

        switch entryContext {
        case .feedCarousel:
            await bootstrapFeedCarouselCatalog(viewerID: viewerID)
        case .profile(let authorID):
            await bootstrapProfileCatalog(authorID: authorID, viewerID: viewerID)
        case .dmReferencedStory:
            await bootstrapDMReferencedCatalog(viewerID: viewerID)
        case .storyArchive:
            await bootstrapStoryArchiveCatalog(viewerID: viewerID)
        }
    }

    private func bootstrapStoryArchiveCatalog(viewerID: ProfileID) async {
        do {
            let archived = try await feed.archivedStories(limit: 200, offset: 0)
            guard archived.contains(where: { $0.id == storyID }) else {
                confirmStoryUnavailable(reason: "archiveStoryMissing")
                return
            }
            let ordered = archived.sorted { $0.createdAt > $1.createdAt }
            cache.seed(stories: ordered)
            applyCatalog(ordered, viewerID: viewerID)
            if let position = sequence.position(of: storyID) {
                authorIndex = position.authorIndex
                slideIndex = position.slideIndex
            }
        } catch {
            confirmStoryUnavailable(reason: "archiveCatalogError")
        }
    }

    private func bootstrapFeedCarouselCatalog(viewerID: ProfileID) async {
        if FeedStoriesCatalogStore.shared.hasFullCatalog,
           !FeedStoriesCatalogStore.shared.catalog.isEmpty
        {
            StoryDebug.log(
                "viewer.catalog",
                "source=store count=\(FeedStoriesCatalogStore.shared.catalog.count)"
            )
            applyCatalog(
                catalogEnsuringTargetStory(FeedStoriesCatalogStore.shared.catalog),
                viewerID: viewerID
            )
            return
        }

        if FeedSupport.isLocalDevelopmentProfile(viewerID) {
            let fixtures = FeedFixtures.stories(viewerID: viewerID)
            FeedStoriesCatalogStore.shared.replace(catalog: fixtures, viewerID: viewerID, isFullCatalog: true)
            applyCatalog(fixtures, viewerID: viewerID)
            return
        }

        do {
            let loaded = try await feed.allActiveStories(for: viewerID)
            StoryDebug.log("viewer.catalog", "source=network count=\(loaded.count)")
            FeedStoriesCatalogStore.shared.replace(catalog: loaded, viewerID: viewerID, isFullCatalog: true)
            cache.seed(stories: loaded)
            applyCatalog(catalogEnsuringTargetStory(loaded), viewerID: viewerID)
        } catch {
            StoryDebug.log("viewer.catalog.error", error.localizedDescription)
            if !FeedStoriesCatalogStore.shared.catalog.isEmpty {
                applyCatalog(
                    catalogEnsuringTargetStory(FeedStoriesCatalogStore.shared.catalog),
                    viewerID: viewerID
                )
            } else if let cached = cache.story(id: storyID),
               ActiveStorySemantics.isActive(createdAt: cached.createdAt)
            {
                FeedStoriesCatalogStore.shared.replace(catalog: [cached], viewerID: viewerID)
                applyCatalog([cached], viewerID: viewerID)
            } else {
                confirmStoryUnavailable(reason: "catalogLoadFailed")
            }
        }
    }

    private func bootstrapProfileCatalog(authorID: ProfileID, viewerID: ProfileID) async {
        var scoped = FeedStoriesCatalogStore.shared.catalog.filter {
            $0.authorProfileID == authorID && ActiveStorySemantics.isActive(createdAt: $0.createdAt)
        }
        if scoped.isEmpty, let cached = cache.story(id: storyID),
           cached.authorProfileID == authorID,
           ActiveStorySemantics.isActive(createdAt: cached.createdAt)
        {
            scoped = [cached]
        }
        if scoped.isEmpty, !FeedSupport.isLocalDevelopmentProfile(viewerID) {
            do {
                let loaded = try await feed.allActiveStories(for: viewerID)
                scoped = loaded.filter { $0.authorProfileID == authorID }
            } catch {
                scoped = []
            }
        }
        if scoped.isEmpty, FeedSupport.isLocalDevelopmentProfile(viewerID) {
            scoped = FeedFixtures.stories(viewerID: viewerID).filter { $0.authorProfileID == authorID }
        }
        guard !scoped.isEmpty else {
            confirmStoryUnavailable(reason: "profileCatalogEmpty")
            return
        }
        applyCatalog(scoped, viewerID: viewerID)
    }

    private func bootstrapDMReferencedCatalog(viewerID: ProfileID) async {
        if FeedSupport.isLocalDevelopmentProfile(viewerID) {
            dismissViewer()
            return
        }

        do {
            if let loaded = try await feed.storyForViewer(id: storyID) {
                cache.seed(loaded)
                applyCatalog([loaded], viewerID: viewerID)
            } else {
                confirmStoryUnavailable(reason: "dmStoryMissing")
            }
        } catch {
            confirmStoryUnavailable(reason: "dmStoryLoadError")
        }
    }

    /// Full-network catalogs can be stale when the viewer opens immediately after publish.
    private func catalogEnsuringTargetStory(_ catalog: [Story]) -> [Story] {
        guard !catalog.contains(where: { $0.id == storyID }) else { return catalog }
        if let cached = cache.story(id: storyID),
           ActiveStorySemantics.isActive(createdAt: cached.createdAt)
        {
            StoryDebug.log("viewer.catalog.merge", "source=cache story=\(storyID.rawValue)")
            var merged = catalog
            merged.removeAll { $0.id == storyID }
            merged.append(cached)
            return merged
        }
        if case .story(let created) = ContentMutationStore.shared.latest,
           created.id == storyID,
           ActiveStorySemantics.isActive(createdAt: created.createdAt)
        {
            StoryDebug.log("viewer.catalog.merge", "source=mutation story=\(storyID.rawValue)")
            var merged = catalog
            merged.removeAll { $0.id == storyID }
            merged.append(created)
            return merged
        }
        if let mine = ViewerActiveStoryStore.shared.activeStory,
           mine.id == storyID,
           ActiveStorySemantics.isActive(createdAt: mine.createdAt)
        {
            StoryDebug.log("viewer.catalog.merge", "source=viewerStore story=\(storyID.rawValue)")
            var merged = catalog
            merged.removeAll { $0.id == storyID }
            merged.append(mine)
            return merged
        }
        return catalog
    }

    private func applyCatalog(_ catalog: [Story], viewerID: ProfileID) {
        self.viewerID = viewerID
        let before = catalog.count
        sequence.install(
            catalog: catalog,
            viewerID: viewerID,
            retainExpiredStories: entryContext.retainsExpiredStoriesInSequence
        )
        var after = 0
        for index in sequence.authorOrder.indices {
            after += sequence.slides(at: index).count
        }
        StoryDebug.log(
            "viewer.sequence.install",
            "input=\(before) slides=\(after) retainExpired=\(entryContext.retainsExpiredStoriesInSequence) containsTarget=\(sequence.position(of: storyID) != nil)"
        )
    }

    private func apply(_ destination: StoryViewerContinuation.Destination) async {
        switch destination {
        case .dismiss:
            if sequence.authorOrder.isEmpty {
                confirmStoryUnavailable(reason: "sequenceEmpty")
            } else {
                dismissViewer(reason: "sequenceDismiss")
            }
        case .showing(let nextAuthor, let nextSlide):
            if !entryContext.allowsCrossAuthorNavigation, nextAuthor != authorIndex {
                dismissViewer()
                return
            }
            authorIndex = nextAuthor
            slideIndex = nextSlide
            await applyCurrentSlide()
        }
    }

    private func applyCurrentSlide() async {
        let slides = currentSlides
        guard slides.indices.contains(slideIndex) else {
            confirmStoryUnavailable(reason: "slideIndexOutOfRange")
            return
        }

        let current = slides[slideIndex]
        let storyActive = ActiveStorySemantics.isActive(createdAt: current.createdAt)
        if !storyActive {
            switch entryContext {
            case .storyArchive, .dmReferencedStory:
                break
            default:
                StoryDebug.log(
                    "viewer.slide.inactive",
                    "story=\(current.id.rawValue) created=\(current.createdAt)"
                )
                await absorbExpiredStories()
                return
            }
        }

        var playable = current
        playable.media = await StorySignedMediaResolver.shared.resolvedPlaybackReference(current.media)
        StoryDebug.logMediaRef(
            "viewer.slide.apply",
            storyID: playable.id.rawValue,
            mediaID: playable.media.id,
            kind: playable.media.kind == .video ? "video" : "image"
        )
        story = playable
        videoTextOverlays = []
        videoPixelSize = .zero
        author = cache.profile(id: current.authorProfileID)
            ?? FollowListFixtures.profile(id: current.authorProfileID)
        if let author {
            cache.seed(author)
        }
        cache.seed(playable)
        if let viewerID {
            isOwner = viewerID == current.authorProfileID
        } else {
            isOwner = false
        }
        phase = .loaded
        StoryDebug.log("viewer.phase", "loaded story=\(current.id.rawValue)")
        playback.bind(story: playable)
        if StoryPlaybackController.isVideoStory(playable) {
            let storyID = playable.id
            let authorID = playable.authorProfileID
            Task { await loadVideoTextOverlays(for: storyID, authorID: authorID) }
        }
        prefetchCurrentStoryEngagement()
        recordStoryViewIfNeeded(for: playable)
    }

    private func recordStoryViewIfNeeded(for story: Story) {
        if let viewerID {
            StoryViewerViewRecords.shared.markViewed(story.id)
            FeedStoriesCatalogStore.shared.markStoryViewed(story.id, viewerID: viewerID)
        }
        guard !isOwner, let viewerID, !FeedSupport.isLocalDevelopmentProfile(viewerID) else { return }
        guard !story.id.rawValue.hasPrefix("dev-") else { return }
        Task {
            try? await feed.recordStoryView(id: story.id)
        }
    }

    /// After catalog install, start on the oldest unviewed slide for the opened author (feed + profile).
    private func resolveInitialSlideForOpenedAuthor() {
        switch entryContext {
        case .storyArchive, .dmReferencedStory:
            return
        case .feedCarousel, .profile:
            break
        }

        let authorID: ProfileID
        switch entryContext {
        case .profile(let id):
            authorID = id
        case .feedCarousel:
            guard let position = sequence.position(of: storyID) else { return }
            guard sequence.authorOrder.indices.contains(position.authorIndex) else { return }
            authorID = sequence.authorOrder[position.authorIndex]
        default:
            return
        }

        guard let openedAuthorIndex = sequence.authorOrder.firstIndex(of: authorID) else { return }
        let slides = sequence.slides(at: openedAuthorIndex)
        guard !slides.isEmpty else { return }

        guard let preferredID = ActiveStorySemantics.preferredEntryStoryID(
            in: slides,
            hasViewed: { StoryViewerViewRecords.shared.hasViewed($0) }
        ), let position = sequence.position(of: preferredID)
        else { return }

        authorIndex = position.authorIndex
        slideIndex = position.slideIndex
    }

    private func prefetchCurrentStoryEngagement() {
        guard !isOwner,
              let story,
              let engagementStore
        else { return }
        engagementStore.prefetch([.story(story.id)])
    }

    private func loadVideoTextOverlays(for storyID: StoryID, authorID: ProfileID) async {
        guard !storyID.rawValue.hasPrefix("dev-"),
              !FeedSupport.isLocalDevelopmentProfile(authorID)
        else { return }
        do {
            let overlays = try await feed.storyTextOverlays(id: storyID)
            guard self.story?.id == storyID else { return }
            videoTextOverlays = overlays
        } catch {
            guard self.story?.id == storyID else { return }
            videoTextOverlays = []
        }
    }

    private func secondsUntilSoonestExpiry(now: Date = Date()) -> TimeInterval {
        var soonest = ActiveStorySemantics.window
        for slides in sequence.slidesByAuthor.values {
            for story in slides {
                let remaining = story.createdAt.addingTimeInterval(ActiveStorySemantics.window)
                    .timeIntervalSince(now)
                if remaining < soonest {
                    soonest = remaining
                }
            }
        }
        if soonest < 0.5 { return 0.5 }
        return min(soonest, 20)
    }

    private func patchInbox(with message: Message, conversation: Conversation, viewerID: ProfileID) {
        let isOpen = inboxStore.activeConversationID == message.conversationID
        inboxStore.patchFromMessage(
            message,
            viewerID: viewerID,
            conversationOpen: isOpen,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation,
            source: "storyReplySend"
        )
        let patchedConversation =
            inboxStore.conversations.first(where: { $0.id == message.conversationID })
            ?? conversation
        ConversationThreadSessionStore.shared.patchMessages(
            viewerID: viewerID,
            conversationID: message.conversationID,
            incoming: [message],
            conversation: patchedConversation
        )
    }
}
