import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class FeedStoryViewerViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
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
    let playback: StoryPlaybackController

    private var sequence = StoryViewerContinuation()
    private var viewerID: ProfileID?

    private let feed: any FeedRepository
    private let messages: any MessageRepository
    private let session: any SessionProviding
    private let cache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let onDismiss: () -> Void

    init(
        storyID: StoryID,
        feed: any FeedRepository,
        messages: any MessageRepository,
        session: any SessionProviding,
        cache: DetailPresentationCache,
        objectStorage: any ObjectStorageProviding,
        inboxStore: MessagesInboxStore? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.storyID = storyID
        self.feed = feed
        self.messages = messages
        self.session = session
        self.cache = cache
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
        self.onDismiss = onDismiss
        self.playback = StoryPlaybackController(storage: objectStorage)
        self.playback.onAdvance = { [weak self] in
            self?.advanceFromPlayback()
        }
        self.playback.onVideoPixelSize = { [weak self] size in
            self?.videoPixelSize = size
        }
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
        viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        await bootstrapCatalogIfNeeded()
        guard let position = sequence.position(of: storyID) else {
            dismissViewer()
            return
        }
        authorIndex = position.authorIndex
        slideIndex = 0
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
        let visibleID = story?.id
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
        await absorbExpiredStories()
        guard phase == .loaded, let current = story, let viewerID else { return }
        guard !FeedSupport.isLocalDevelopmentProfile(viewerID) else { return }
        do {
            let fresh = try await feed.story(id: current.id)
            if fresh == nil {
                await absorbRemovedStory(current.id)
            }
        } catch {
            return
        }
    }

    /// While the viewer is open, expire slides on time and notice deletes from another device.
    func watchStoryLifecycle() async {
        while !Task.isCancelled {
            await revalidateVisibleStory()
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
        guard authorIndex > 0 else {
            dismissViewer()
            return
        }
        authorIndex -= 1
        slideIndex = 0
        Task { await applyCurrentSlide() }
    }

    func dismissViewer() {
        playback.stopPlayback()
        onDismiss()
    }

    func clearDeleteError() {
        deleteErrorMessage = nil
    }

    func clearReplyError() {
        replyErrorMessage = nil
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
        if authorIndex < sequence.authorOrder.count - 1 {
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
        if authorIndex > 0 {
            authorIndex -= 1
            let previousSlides = sequence.slides(at: authorIndex)
            slideIndex = max(0, previousSlides.count - 1)
            Task { await applyCurrentSlide() }
            return
        }
        dismissViewer()
    }

    private func bootstrapCatalogIfNeeded() async {
        if FeedStoriesCatalogStore.shared.hasFullCatalog,
           !FeedStoriesCatalogStore.shared.catalog.isEmpty,
           let viewerID = viewerID ?? FeedStoriesCatalogStore.shared.viewerID
        {
            applyCatalog(FeedStoriesCatalogStore.shared.catalog, viewerID: viewerID)
            return
        }

        guard let viewerID else {
            dismissViewer()
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
            FeedStoriesCatalogStore.shared.replace(catalog: loaded, viewerID: viewerID, isFullCatalog: true)
            cache.seed(stories: loaded)
            applyCatalog(loaded, viewerID: viewerID)
        } catch {
            if !FeedStoriesCatalogStore.shared.catalog.isEmpty {
                applyCatalog(FeedStoriesCatalogStore.shared.catalog, viewerID: viewerID)
            } else if let cached = cache.story(id: storyID),
               ActiveStorySemantics.isActive(createdAt: cached.createdAt)
            {
                FeedStoriesCatalogStore.shared.replace(catalog: [cached], viewerID: viewerID)
                applyCatalog([cached], viewerID: viewerID)
            } else {
                dismissViewer()
            }
        }
    }

    private func applyCatalog(_ catalog: [Story], viewerID: ProfileID) {
        self.viewerID = viewerID
        sequence.install(catalog: catalog, viewerID: viewerID)
    }

    private func apply(_ destination: StoryViewerContinuation.Destination) async {
        switch destination {
        case .dismiss:
            dismissViewer()
        case .showing(let nextAuthor, let nextSlide):
            authorIndex = nextAuthor
            slideIndex = nextSlide
            await applyCurrentSlide()
        }
    }

    private func applyCurrentSlide() async {
        let slides = currentSlides
        guard slides.indices.contains(slideIndex) else {
            dismissViewer()
            return
        }

        let current = slides[slideIndex]
        guard ActiveStorySemantics.isActive(createdAt: current.createdAt) else {
            await absorbExpiredStories()
            return
        }

        story = current
        videoTextOverlays = []
        videoPixelSize = .zero
        author = cache.profile(id: current.authorProfileID)
            ?? FollowListFixtures.profile(id: current.authorProfileID)
        if let author {
            cache.seed(author)
        }
        cache.seed(current)
        if let viewerID {
            isOwner = viewerID == current.authorProfileID
        } else {
            isOwner = false
        }
        phase = .loaded
        playback.bind(story: current)
        if StoryPlaybackController.isVideoStory(current) {
            let storyID = current.id
            let authorID = current.authorProfileID
            Task { await loadVideoTextOverlays(for: storyID, authorID: authorID) }
        }
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
