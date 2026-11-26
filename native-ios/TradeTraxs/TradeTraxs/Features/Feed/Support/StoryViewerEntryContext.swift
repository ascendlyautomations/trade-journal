import Foundation

/// Controls which stories appear in the viewer and whether playback can cross authors.
nonisolated enum StoryViewerEntryContext: Hashable, Codable, Sendable {
    /// Feed strip / deep link, stories from followed users in carousel order.
    case feedCarousel
    /// Profile header ring for one user only.
    case profile(authorID: ProfileID)
    /// DM story reply or share preview, single referenced story.
    case dmReferencedStory
}

extension StoryViewerEntryContext {
    var allowsCrossAuthorNavigation: Bool {
        switch self {
        case .feedCarousel: return true
        case .profile, .dmReferencedStory: return false
        }
    }

    var profileAuthorID: ProfileID? {
        if case .profile(let authorID) = self { return authorID }
        return nil
    }
}