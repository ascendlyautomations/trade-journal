import Foundation

nonisolated struct DefaultFeedRepository: FeedRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func feed(scope: FeedScope, page: PageRequest) async throws -> CursorPage<FeedItem> {
        _ = scope
        // Public trade posts power the social feed today.
        let rows: [FeedDTO.Post] = try await supabase.database.select(
            FeedDTO.Post.self,
            from: "posts",
            query: SupabaseQuery.page(page) + [SupabaseQuery.select("*")]
        )
        let items: [FeedItem] = rows.compactMap { post in
            guard let id = post.id, let author = post.user_id else { return nil }
            let created = ISO8601.date(from: post.created_at) ?? Date()
            return FeedItem(
                id: id,
                kind: post.trade_id == nil ? .post : .trade,
                authorProfileID: ProfileID(author),
                createdAt: created,
                tradeID: post.trade_id.map { TradeID($0) },
                postID: PostID(id),
                reelID: nil,
                storyID: nil,
                achievementID: nil,
                caption: post.body ?? post.content,
                likeCount: 0,
                commentCount: 0,
                viewerHasLiked: false
            )
        }
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func post(id: PostID) async throws -> Post {
        let dto: FeedDTO.Post = try await supabase.database.selectOne(
            FeedDTO.Post.self,
            from: "posts",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        )
        return try mapPost(dto)
    }

    func createPost(_ post: Post) async throws -> Post {
        struct Body: Encodable {
            var user_id: String
            var content: String
            var trade_id: String?
        }
        let body = Body(
            user_id: post.authorProfileID.rawValue,
            content: post.body,
            trade_id: post.linkedTradeID?.rawValue
        )
        let dto: FeedDTO.Post = try await supabase.database.insert(
            body,
            into: "posts",
            returning: FeedDTO.Post.self
        )
        return try mapPost(dto)
    }

    func deletePost(id: PostID) async throws {
        try await supabase.database.delete(
            from: "posts",
            query: [SupabaseQuery.eq("id", id.rawValue)]
        )
    }

    func comments(for postID: PostID, page: PageRequest) async throws -> CursorPage<Comment> {
        let rows: [FeedDTO.Comment] = try await supabase.database.select(
            FeedDTO.Comment.self,
            from: "profile_post_comments",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("post_id", postID.rawValue),
            ]
        )
        let items = rows.compactMap(mapComment)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func addComment(_ comment: Comment) async throws -> Comment {
        struct Body: Encodable {
            var post_id: String?
            var user_id: String
            var content: String
            var parent_comment_id: String?
        }
        let body = Body(
            post_id: comment.postID?.rawValue,
            user_id: comment.authorProfileID.rawValue,
            content: comment.body,
            parent_comment_id: comment.parentCommentID?.rawValue
        )
        let dto: FeedDTO.Comment = try await supabase.database.insert(
            body,
            into: "profile_post_comments",
            returning: FeedDTO.Comment.self
        )
        guard let mapped = mapComment(dto) else {
            throw AppError.unknown(message: "Failed to map comment")
        }
        return mapped
    }

    func setReaction(on item: FeedItem, kind: ReactionKind, isActive: Bool) async throws {
        guard kind == .like, let postID = item.postID else { return }
        struct Body: Encodable, Decodable {
            var post_id: String
            var user_id: String
        }
        // Likes are constrained by RLS to auth.uid(); author id is only used for delete filters
        // when the active session matches.
        let userID = item.authorProfileID.rawValue
        if isActive {
            _ = try await supabase.database.insert(
                Body(post_id: postID.rawValue, user_id: userID),
                into: "profile_post_likes",
                returning: Body.self
            )
        } else {
            try await supabase.database.delete(
                from: "profile_post_likes",
                query: [
                    SupabaseQuery.eq("post_id", postID.rawValue),
                    SupabaseQuery.eq("user_id", userID),
                ]
            )
        }
    }

    func stories(for viewer: ProfileID) async throws -> [Story] {
        _ = viewer
        struct Row: Codable {
            var id: String?
            var user_id: String?
            var media_url: String?
            var created_at: String?
            var expires_at: String?
        }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "stories",
            query: [
                SupabaseQuery.select("id,user_id,media_url,created_at,expires_at"),
                URLQueryItem(name: "expires_at", value: "gt.\(ISO8601.string(from: Date()))"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50"),
            ]
        )
        return rows.compactMap { row in
            guard let id = row.id, let author = row.user_id, let media = row.media_url else { return nil }
            return Story(
                id: StoryID(id),
                authorProfileID: ProfileID(author),
                media: MediaReference(id: media, kind: .image, altText: nil),
                expiresAt: ISO8601.date(from: row.expires_at) ?? Date().addingTimeInterval(86_400),
                createdAt: ISO8601.date(from: row.created_at) ?? Date(),
                viewerHasSeen: false
            )
        }
    }

    func reel(id: ReelID) async throws -> Reel {
        struct Row: Codable {
            var id: String?
            var user_id: String?
            var video_url: String?
            var thumbnail_url: String?
            var caption: String?
            var trade_id: String?
            var created_at: String?
        }
        let row: Row = try await supabase.database.selectOne(
            Row.self,
            from: "reels",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        )
        guard let reelID = row.id, let author = row.user_id, let video = row.video_url else {
            throw AppError.domain(.notFound(entity: "reel", id: id.rawValue))
        }
        return Reel(
            id: ReelID(reelID),
            authorProfileID: ProfileID(author),
            video: MediaReference(id: video, kind: .video, altText: nil),
            thumbnail: row.thumbnail_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
            caption: row.caption,
            visibility: .public,
            linkedTradeID: row.trade_id.map { TradeID($0) },
            createdAt: ISO8601.date(from: row.created_at) ?? Date()
        )
    }

    func createReel(_ reel: Reel) async throws -> Reel {
        struct Body: Encodable {
            var user_id: String
            var video_url: String
            var thumbnail_url: String?
            var caption: String?
            var trade_id: String?
        }
        let body = Body(
            user_id: reel.authorProfileID.rawValue,
            video_url: reel.video.id,
            thumbnail_url: reel.thumbnail?.id,
            caption: reel.caption,
            trade_id: reel.linkedTradeID?.rawValue
        )
        struct Row: Codable {
            var id: String?
            var user_id: String?
            var video_url: String?
            var thumbnail_url: String?
            var caption: String?
            var trade_id: String?
            var created_at: String?
        }
        let row: Row = try await supabase.database.insert(body, into: "reels", returning: Row.self)
        guard let id = row.id, let author = row.user_id, let video = row.video_url else {
            return reel
        }
        return Reel(
            id: ReelID(id),
            authorProfileID: ProfileID(author),
            video: MediaReference(id: video, kind: .video, altText: nil),
            thumbnail: row.thumbnail_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
            caption: row.caption,
            visibility: reel.visibility,
            linkedTradeID: row.trade_id.map { TradeID($0) },
            createdAt: ISO8601.date(from: row.created_at) ?? Date()
        )
    }

    private func mapPost(_ dto: FeedDTO.Post) throws -> Post {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        guard let author = dto.user_id else { throw MappingError.missingField("user_id") }
        let created = ISO8601.date(from: dto.created_at) ?? Date()
        return Post(
            id: PostID(id),
            authorProfileID: ProfileID(author),
            body: dto.body ?? dto.content ?? "",
            media: [],
            visibility: .public,
            linkedTradeID: dto.trade_id.map { TradeID($0) },
            createdAt: created,
            updatedAt: ISO8601.date(from: dto.updated_at) ?? created
        )
    }

    private func mapComment(_ dto: FeedDTO.Comment) -> Comment? {
        guard let id = dto.id else { return nil }
        let author = dto.user_id
        guard let author else { return nil }
        return Comment(
            id: CommentID(id),
            postID: dto.post_id.map { PostID($0) },
            tradeID: nil,
            reelID: nil,
            authorProfileID: ProfileID(author),
            body: dto.body ?? dto.content ?? "",
            parentCommentID: dto.parent_comment_id.map { CommentID($0) },
            createdAt: ISO8601.date(from: dto.created_at) ?? Date()
        )
    }
}
