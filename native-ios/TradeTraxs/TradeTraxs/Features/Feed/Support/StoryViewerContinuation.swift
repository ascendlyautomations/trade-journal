import Foundation

/// In-viewer story sequence. A removed or expired slide moves forward, then to the
/// next author, then dismisses. It never stays on a missing slide.
nonisolated struct StoryViewerContinuation: Equatable, Sendable {
    var authorOrder: [ProfileID] = []
    var slidesByAuthor: [ProfileID: [Story]] = [:]

    enum Destination: Equatable, Sendable {
        case showing(authorIndex: Int, slideIndex: Int)
        case dismiss
    }

    mutating func install(catalog: [Story], viewerID: ProfileID, now: Date = Date()) {
        let active = ActiveStorySemantics.filterActive(catalog, now: now)
        slidesByAuthor = ActiveStorySemantics.groupByAuthor(active)
        authorOrder = ActiveStorySemantics.authorOrder(from: active, viewerID: viewerID)
            .filter { !(slidesByAuthor[$0] ?? []).isEmpty }
    }

    func position(of storyID: StoryID) -> (authorIndex: Int, slideIndex: Int)? {
        for (authorIndex, authorID) in authorOrder.enumerated() {
            guard let slides = slidesByAuthor[authorID] else { continue }
            if let slideIndex = slides.firstIndex(where: { $0.id == storyID }) {
                return (authorIndex, slideIndex)
            }
        }
        return nil
    }

    func slides(at authorIndex: Int) -> [Story] {
        guard authorOrder.indices.contains(authorIndex) else { return [] }
        return slidesByAuthor[authorOrder[authorIndex]] ?? []
    }

    /// Drops stories that are no longer active. The viewed slide moves forward when it is one of them.
    mutating func dropInactive(
        viewingAuthorIndex: Int,
        viewingSlideIndex: Int,
        now: Date = Date()
    ) -> Destination {
        var expired = Set<StoryID>()
        for slides in slidesByAuthor.values {
            for story in slides where !ActiveStorySemantics.isActive(createdAt: story.createdAt, now: now) {
                expired.insert(story.id)
            }
        }
        guard !expired.isEmpty else {
            return stay(viewingAuthorIndex: viewingAuthorIndex, viewingSlideIndex: viewingSlideIndex)
        }
        return remove(
            storyIDs: expired,
            viewingAuthorIndex: viewingAuthorIndex,
            viewingSlideIndex: viewingSlideIndex
        )
    }

    mutating func remove(
        storyIDs: Set<StoryID>,
        viewingAuthorIndex: Int,
        viewingSlideIndex: Int
    ) -> Destination {
        let viewed = story(atAuthor: viewingAuthorIndex, slide: viewingSlideIndex)
        let followingAuthorIDs = Array(authorOrder.dropFirst(viewingAuthorIndex + 1))
        var removedViewed = false

        for authorID in Array(slidesByAuthor.keys) {
            let before = slidesByAuthor[authorID] ?? []
            let after = before.filter { !storyIDs.contains($0.id) }
            if let viewedID = viewed?.id,
               before.contains(where: { $0.id == viewedID }),
               !after.contains(where: { $0.id == viewedID })
            {
                removedViewed = true
            }
            if after.isEmpty {
                slidesByAuthor[authorID] = nil
            } else if after.count != before.count {
                slidesByAuthor[authorID] = after
            }
        }
        authorOrder.removeAll { slidesByAuthor[$0]?.isEmpty != false }

        guard removedViewed else {
            if let viewedID = viewed?.id, let position = position(of: viewedID) {
                return .showing(authorIndex: position.authorIndex, slideIndex: position.slideIndex)
            }
            return stay(viewingAuthorIndex: viewingAuthorIndex, viewingSlideIndex: viewingSlideIndex)
        }

        if let viewedAuthor = viewed?.authorProfileID,
           let slides = slidesByAuthor[viewedAuthor],
           viewingSlideIndex < slides.count,
           let authorIndex = authorOrder.firstIndex(of: viewedAuthor)
        {
            return .showing(authorIndex: authorIndex, slideIndex: viewingSlideIndex)
        }

        for authorID in followingAuthorIDs {
            guard let slides = slidesByAuthor[authorID], !slides.isEmpty,
                  let authorIndex = authorOrder.firstIndex(of: authorID)
            else { continue }
            return .showing(authorIndex: authorIndex, slideIndex: 0)
        }

        return .dismiss
    }

    private func story(atAuthor authorIndex: Int, slide slideIndex: Int) -> Story? {
        let slides = slides(at: authorIndex)
        guard slides.indices.contains(slideIndex) else { return nil }
        return slides[slideIndex]
    }

    private func stay(viewingAuthorIndex: Int, viewingSlideIndex: Int) -> Destination {
        guard !authorOrder.isEmpty else { return .dismiss }
        let authorIndex = min(max(viewingAuthorIndex, 0), authorOrder.count - 1)
        let slides = slides(at: authorIndex)
        guard !slides.isEmpty else { return .dismiss }
        let slideIndex = min(max(viewingSlideIndex, 0), slides.count - 1)
        return .showing(authorIndex: authorIndex, slideIndex: slideIndex)
    }
}
