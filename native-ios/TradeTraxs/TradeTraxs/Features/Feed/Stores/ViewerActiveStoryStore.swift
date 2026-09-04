import Foundation
import Observation

/// Session-local indicator for whether the signed-in user has an active story.
///
/// Updated from Feed bootstrap/cache and ``ContentMutationStore`` — no Profile-specific fetch.
@Observable
@MainActor
final class ViewerActiveStoryStore {
    static let shared = ViewerActiveStoryStore()

    private(set) var activeStory: Story?
    private(set) var viewerID: ProfileID?

    private init() {}

    func sync(viewerID: ProfileID, stories: [Story], now: Date = Date()) {
        self.viewerID = viewerID
        activeStory = Self.resolveActiveViewerStory(from: stories, viewerID: viewerID, now: now)
    }

    func applyStoryCreated(_ story: Story, viewerID: ProfileID, now: Date = Date()) {
        guard story.authorProfileID == viewerID else { return }
        guard ActiveStorySemantics.isActive(createdAt: story.createdAt, now: now) else { return }
        self.viewerID = viewerID
        activeStory = story
    }

    func applyStoryDeleted(_ storyID: StoryID) {
        if activeStory?.id == storyID {
            activeStory = nil
        }
    }

    /// Reads the latest Following-scope Feed cache without networking.
    func reconcileFromFeedCache(viewerID: ProfileID, now: Date = Date()) {
        if let story = FeedSessionStore.shared.activeViewerStory(viewerID: viewerID, now: now) {
            self.viewerID = viewerID
            activeStory = story
        }
    }

    func reconcileExpired(now: Date = Date()) {
        guard let story = activeStory else { return }
        if !ActiveStorySemantics.isActive(createdAt: story.createdAt, now: now) {
            activeStory = nil
        }
    }

    func invalidate() {
        activeStory = nil
        viewerID = nil
    }

    static func resolveActiveViewerStory(
        from stories: [Story],
        viewerID: ProfileID,
        now: Date = Date()
    ) -> Story? {
        guard let story = stories.first(where: { $0.authorProfileID == viewerID }) else { return nil }
        return ActiveStorySemantics.isActive(createdAt: story.createdAt, now: now) ? story : nil
    }
}
