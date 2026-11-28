import Foundation

/// Session-scoped story view flags for the authenticated viewer.
///
/// Supplements durable ``story_views`` / bootstrap `viewer_has_seen` with in-session marks
/// before the next RPC refresh (not a substitute for server state; cleared on logout).
@MainActor
final class StoryViewerViewRecords {
    static let shared = StoryViewerViewRecords()

    private var viewerID: ProfileID?
    private var viewedIDs: Set<StoryID> = []

    private init() {}

    func rebindIfNeeded(viewerID: ProfileID) {
        guard self.viewerID != viewerID else { return }
        self.viewerID = viewerID
        viewedIDs.removeAll()
    }

    func markViewed(_ storyID: StoryID) {
        viewedIDs.insert(storyID)
    }

    func hasViewed(_ story: Story) -> Bool {
        story.viewerHasSeen || viewedIDs.contains(story.id)
    }

    func invalidate() {
        viewerID = nil
        viewedIDs.removeAll()
    }
}