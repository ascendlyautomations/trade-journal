import Foundation

/// Session-scoped catalog of all active stories for carousel navigation.
@MainActor
final class FeedStoriesCatalogStore {
    static let shared = FeedStoriesCatalogStore()

    private(set) var catalog: [Story] = []
    private(set) var viewerID: ProfileID?
    private(set) var hasFullCatalog = false

    private init() {}

    func replace(catalog: [Story], viewerID: ProfileID, isFullCatalog: Bool = false) {
        let active = ActiveStorySemantics.filterActive(catalog)
        self.catalog = active
        self.viewerID = viewerID
        if isFullCatalog {
            hasFullCatalog = true
        }
    }

    func mergeAuthorStories(_ stories: [Story], authorID: ProfileID, viewerID: ProfileID) {
        var merged = catalog.filter { $0.authorProfileID != authorID }
        merged.append(contentsOf: ActiveStorySemantics.filterActive(stories))
        replace(catalog: merged, viewerID: viewerID)
    }

    func removeStory(id: StoryID) {
        catalog.removeAll { $0.id == id }
    }

    func markStoryViewed(_ storyID: StoryID, viewerID: ProfileID) {
        self.viewerID = viewerID
        catalog = catalog.map { story in
            guard story.id == storyID else { return story }
            var copy = story
            copy.viewerHasSeen = true
            return copy
        }
    }

    /// Inserts or replaces one active story (e.g. right after publish) without discarding the full catalog.
    func upsertStory(_ story: Story, viewerID: ProfileID) {
        guard ActiveStorySemantics.isActive(createdAt: story.createdAt) else { return }
        self.viewerID = viewerID
        catalog.removeAll { $0.id == story.id }
        catalog.append(story)
    }

    func invalidate() {
        catalog = []
        viewerID = nil
        hasFullCatalog = false
    }

    var storiesByAuthor: [ProfileID: [Story]] {
        ActiveStorySemantics.groupByAuthor(catalog)
    }

    func authorOrder(viewerID: ProfileID) -> [ProfileID] {
        ActiveStorySemantics.authorOrder(from: catalog, viewerID: viewerID)
    }

    func slides(for authorID: ProfileID) -> [Story] {
        storiesByAuthor[authorID] ?? []
    }
}
