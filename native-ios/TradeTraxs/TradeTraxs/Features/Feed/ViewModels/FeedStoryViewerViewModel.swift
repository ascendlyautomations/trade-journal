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

    let storyID: StoryID
    let playback: StoryPlaybackController

    private var authorOrder: [ProfileID] = []
    private var storiesByAuthor: [ProfileID: [Story]] = [:]
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
        guard authorIndex >= 0, authorIndex < authorOrder.count else { return [] }
        return storiesByAuthor[authorOrder[authorIndex]] ?? []
    }

    func loadIfNeeded() async {
        viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        await bootstrapCatalogIfNeeded()
        guard resolveInitialPosition() else {
            phase = .unavailable
            return
        }
        await applyCurrentSlide()
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
        guard authorIndex < authorOrder.count - 1 else {
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
            cache.removeStory(id: currentStory.id)
            ContentMutationStore.shared.noteStoryDeleted(currentStory.id)
            FeedStoriesCatalogStore.shared.removeStory(id: currentStory.id)
            removeCurrentSlideFromCatalog(storyID: currentStory.id)
            ExperienceHaptics.play(.success)

            if authorOrder.isEmpty {
                dismissViewer()
                return true
            }
            clampIndices()
            if currentSlides.isEmpty {
                if authorIndex > 0 {
                    authorIndex -= 1
                    slideIndex = max(0, (storiesByAuthor[authorOrder[authorIndex]] ?? []).count - 1)
                } else {
                    dismissViewer()
                    return true
                }
            } else if slideIndex >= currentSlides.count {
                slideIndex = max(0, currentSlides.count - 1)
            }
            await applyCurrentSlide()
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
        if authorIndex < authorOrder.count - 1 {
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
            let previousSlides = storiesByAuthor[authorOrder[authorIndex]] ?? []
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
            phase = .unavailable
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
                phase = .unavailable
            }
        }
    }

    private func applyCatalog(_ catalog: [Story], viewerID: ProfileID) {
        self.viewerID = viewerID
        storiesByAuthor = ActiveStorySemantics.groupByAuthor(catalog)
        authorOrder = ActiveStorySemantics.authorOrder(from: catalog, viewerID: viewerID)
            .filter { !(storiesByAuthor[$0] ?? []).isEmpty }
    }

    private func resolveInitialPosition() -> Bool {
        guard !authorOrder.isEmpty else { return false }

        for (authorIdx, authorID) in authorOrder.enumerated() {
            guard let slides = storiesByAuthor[authorID] else { continue }
            if slides.contains(where: { $0.id == storyID }) {
                authorIndex = authorIdx
                slideIndex = 0
                return true
            }
        }

        authorIndex = 0
        slideIndex = 0
        return true
    }

    private func applyCurrentSlide() async {
        let slides = currentSlides
        guard !slides.isEmpty, slideIndex < slides.count else {
            phase = .unavailable
            return
        }

        let current = slides[slideIndex]
        story = current
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
    }

    private func removeCurrentSlideFromCatalog(storyID: StoryID) {
        for authorID in storiesByAuthor.keys {
            storiesByAuthor[authorID]?.removeAll { $0.id == storyID }
            if storiesByAuthor[authorID]?.isEmpty == true {
                storiesByAuthor[authorID] = nil
            }
        }
        authorOrder.removeAll { storiesByAuthor[$0]?.isEmpty != false }
    }

    private func clampIndices() {
        if authorOrder.isEmpty {
            authorIndex = 0
            slideIndex = 0
            return
        }
        authorIndex = min(max(authorIndex, 0), authorOrder.count - 1)
        let slides = currentSlides
        slideIndex = min(max(slideIndex, 0), max(slides.count - 1, 0))
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
