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

    let storyID: StoryID

    private let feed: any FeedRepository
    private let session: any SessionProviding
    private let cache: DetailPresentationCache
    private let onDismiss: () -> Void

    init(
        storyID: StoryID,
        feed: any FeedRepository,
        session: any SessionProviding,
        cache: DetailPresentationCache,
        onDismiss: @escaping () -> Void
    ) {
        self.storyID = storyID
        self.feed = feed
        self.session = session
        self.cache = cache
        self.onDismiss = onDismiss
    }

    func loadIfNeeded() async {
        if let cached = cache.story(id: storyID),
           ActiveStorySemantics.isActive(createdAt: cached.createdAt)
        {
            await applyLoaded(cached)
            return
        }

        do {
            if let fetched = try await feed.story(id: storyID) {
                cache.seed(fetched)
                await applyLoaded(fetched)
            } else {
                phase = .unavailable
            }
        } catch {
            phase = .unavailable
        }
    }

    private func applyLoaded(_ cached: Story) async {
        story = cached
        author = cache.profile(id: cached.authorProfileID)
        if let viewer = await session.currentUserID {
            isOwner = viewer.rawValue == cached.authorProfileID.rawValue
        } else {
            isOwner = false
        }
        phase = .loaded
    }

    func clearDeleteError() {
        deleteErrorMessage = nil
    }

    func deleteStory() async -> Bool {
        guard isOwner, !isDeleting, story != nil else { return false }
        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }

        do {
            if let viewer = await session.currentUserID,
               !viewer.rawValue.hasPrefix("dev.")
            {
                try await feed.deleteStory(id: storyID)
            }
            cache.removeStory(id: storyID)
            ContentMutationStore.shared.noteStoryDeleted(storyID)
            ExperienceHaptics.play(.success)
            onDismiss()
            return true
        } catch {
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return false
        }
    }
}
