import Foundation

enum CreatePostFixtures {
    static let viewerID = ProfileID("dev.createpost.viewer")

    static func samplePost(author: ProfileID = viewerID, body: String = "Fixture wall post") -> Post {
        Post(
            id: PostID("dev.createpost.\(UUID().uuidString)"),
            authorProfileID: author,
            body: body,
            media: [],
            visibility: .public,
            linkedTradeID: nil,
            isPinned: false,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
