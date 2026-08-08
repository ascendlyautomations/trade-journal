import Foundation

nonisolated protocol CreatePostUseCase: Sendable {
    func execute(body: String, media: [MediaReference], visibility: ContentVisibility, linkedTradeID: TradeID?) async throws -> Post
}

nonisolated protocol LikePostUseCase: Sendable {
    func execute(postID: PostID, isLiked: Bool) async throws
}

nonisolated protocol CommentOnPostUseCase: Sendable {
    func execute(postID: PostID, body: String, parentCommentID: CommentID?) async throws -> Comment
}
