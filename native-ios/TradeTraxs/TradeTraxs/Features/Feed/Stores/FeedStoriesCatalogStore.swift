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
