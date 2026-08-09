import Foundation

nonisolated protocol FeedRepository: Sendable {
    func feed(scope: FeedScope, page: PageRequest) async throws -> CursorPage<FeedItem>
    func post(id: PostID) async throws -> Post
    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post>
    func createPost(_ post: Post) async throws -> Post
    func deletePost(id: PostID) async throws
    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment>
    func addComment(_ comment: Comment) async throws -> Comment
    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws
    func stories(for viewer: ProfileID) async throws -> [Story]
    func reel(id: ReelID) async throws -> Reel
    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel>
    /// Web `fetchUserProfileReels` — Profile Clips tab (trade-linked visibility filter).
    func profileReels(for profileID: ProfileID) async throws -> [Reel]
    func createReel(_ reel: Reel) async throws -> Reel
}
