import Foundation

nonisolated struct StoryDmMediaAccess: Hashable, Sendable {
    var allowed: Bool
    var reason: String
    var storyID: StoryID?
    var ownerID: ProfileID?
    var createdAt: Date?
    var storagePath: String?
    var imageURL: String?
}