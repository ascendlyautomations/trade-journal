import Foundation
import OSLog

nonisolated struct DefaultFeedRepository: FeedRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

    /// Exact web `PROFILE_REELS_SELECT` from `lib/reels.ts`.
    private static let profileReelsSelect =
        "id,user_id,caption,video_url,thumbnail_url,duration_seconds,visibility,trade_id,kind,created_at,updated_at,trades!reels_trade_id_fkey(id,public_description,is_public,ticker,direction,pnl,rr)"

    /// Exact web `REEL_ROW_SELECT` fallback.
    private static let reelRowSelect =
        "id,user_id,caption,video_url,thumbnail_url,duration_seconds,visibility,trade_id,kind,created_at,updated_at"

    private static let reelTradeJoinSelect =
        "id,public_description,is_public,ticker,direction,pnl,rr"

    /// Web `FEED_POSTS_SELECT` profile join — enough for FeedItem + TradeRepository hydrate.
    private static let tradeFeedSelect =
        "id,user_id,trade_id,created_at,image_url,profiles(username,avatar_url,name)"

    /// Web `FEED_PROFILE_POSTS_SELECT` (core columns + profiles embed).
    private static let profileFeedSelect =
        "id,user_id,content,image_url,created_at,profiles(username,avatar_url,name)"

    /// Web `FEED_REELS_SELECT` without trade embed (list identity + profiles).
    private static let reelFeedSelect =
        "id,user_id,caption,video_url,thumbnail_url,duration_seconds,visibility,trade_id,kind,created_at,profiles(username,avatar_url,name)"

    /// Web `FEED_ACHIEVEMENT_POSTS_SELECT` (identity + public achievement + profiles).
    private static let achievementFeedSelect =
        "id,user_id,achievement_id,created_at,achievements(id,title,description,achievement_type,badge_key,tier,value_text,value_numeric,currency,image_url,achieved_at,is_public,is_featured,category,firm,metadata),profiles(username,avatar_url,name)"

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.session = session
    }

    /// Web `topUpMergedFeedBuffer` first page — trades + profile_posts + reels + achievement_posts.
    func feed(scope: FeedScope, page: PageRequest) async throws -> CursorPage<FeedItem> {
        let viewerID = await session.currentUserID?.rawValue
        let followingIDs = try await fetchFollowingIDs(viewerID: viewerID)

        if scope == .following, followingIDs.isEmpty {
            return CursorPage(items: [], nextCursor: nil)
        }

        async let tradeBatch = fetchTradeFeedBatch(
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        )
        async let profileBatch = fetchProfileFeedBatch(
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        )
        async let reelBatch = fetchReelFeedBatch(
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        )
        async let achievementBatch = fetchAchievementFeedBatch(
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        )

        let (trades, posts, reels, achievements) = try await (
            tradeBatch, profileBatch, reelBatch, achievementBatch
        )

        // Web `dedupeFeedItems` — skip trade-attached reels (they render on the trade card).
        let standaloneReels = reels.filter { item in
            guard let tradeID = item.tradeID?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return true }
            return tradeID.isEmpty
        }

        var merged = trades + posts + standaloneReels + achievements
        merged.sort { $0.createdAt > $1.createdAt }

        let limited = Array(merged.prefix(page.limit))
        let next = limited.count >= page.limit
            ? ISO8601.string(from: limited.last?.createdAt ?? Date())
            : nil
        return CursorPage(items: limited, nextCursor: next)
    }

    // MARK: - Web feed batches (`lib/feedContent.ts`)

    private func fetchFollowingIDs(viewerID: String?) async throws -> [String] {
        guard let viewerID, !viewerID.isEmpty else { return [] }
        struct Row: Codable { var following_id: String? }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "followers",
            query: [
                SupabaseQuery.select("following_id"),
                SupabaseQuery.eq("follower_id", viewerID),
            ]
        )
        return rows.compactMap { row in
            let id = row.following_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty ? nil : id
        }
    }

    private func scopeQueryItems(
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String]
    ) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []
        if let viewerID, !viewerID.isEmpty {
            items.append(URLQueryItem(name: "user_id", value: "neq.\(viewerID)"))
        }
        switch scope {
        case .following:
            guard !followingIDs.isEmpty else { return nil }
            items.append(SupabaseQuery.isIn("user_id", followingIDs))
        case .global:
            if !followingIDs.isEmpty {
                let joined = followingIDs.joined(separator: ",")
                items.append(URLQueryItem(name: "user_id", value: "not.in.(\(joined))"))
            }
        }
        return items
    }

    private func feedPageQuery(
        select: String,
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String],
        page: PageRequest,
        extra: [URLQueryItem] = []
    ) -> [URLQueryItem]? {
        guard let scoped = scopeQueryItems(
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs
        ) else { return nil }
        return [SupabaseQuery.select(select)]
            + SupabaseQuery.page(page)
            + scoped
            + extra
    }

    private func fetchTradeFeedBatch(
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String],
        page: PageRequest
    ) async throws -> [FeedItem] {
        guard let query = feedPageQuery(
            select: Self.tradeFeedSelect,
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        ) else { return [] }
        let rows: [FeedDTO.TradeFeedRow] = try await supabase.database.select(
            FeedDTO.TradeFeedRow.self,
            from: "posts",
            query: query
        )
        return rows.compactMap { row -> FeedItem? in
            guard let id = row.id, let author = row.user_id else { return nil }
            // Web `normalizeTradeFeedItem` — posts table rows are trade feed cards.
            return makeFeedItem(
                id: id,
                kind: .trade,
                author: author,
                createdAt: row.created_at,
                tradeID: row.trade_id,
                postID: id,
                reelID: nil,
                achievementID: nil,
                caption: nil,
                mediaURL: row.image_url,
                profiles: row.profiles?.profile
            )
        }
    }

    private func fetchProfileFeedBatch(
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String],
        page: PageRequest
    ) async throws -> [FeedItem] {
        guard let query = feedPageQuery(
            select: Self.profileFeedSelect,
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        ) else { return [] }
        let rows: [FeedDTO.ProfileFeedRow] = try await supabase.database.select(
            FeedDTO.ProfileFeedRow.self,
            from: "profile_posts",
            query: query
        )
        return rows.compactMap { row -> FeedItem? in
            guard let id = row.id, let author = row.user_id else { return nil }
            return makeFeedItem(
                id: id,
                kind: .post,
                author: author,
                createdAt: row.created_at,
                tradeID: nil,
                postID: id,
                reelID: nil,
                achievementID: nil,
                caption: row.content,
                mediaURL: row.image_url,
                profiles: row.profiles?.profile
            )
        }
    }

    private func fetchReelFeedBatch(
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String],
        page: PageRequest
    ) async throws -> [FeedItem] {
        guard let query = feedPageQuery(
            select: Self.reelFeedSelect,
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        ) else { return [] }
        let rows: [FeedDTO.ReelFeedRow] = try await supabase.database.select(
            FeedDTO.ReelFeedRow.self,
            from: "reels",
            query: query
        )
        return rows.compactMap { row -> FeedItem? in
            guard let id = row.id, let author = row.user_id else { return nil }
            return makeFeedItem(
                id: id,
                kind: .reel,
                author: author,
                createdAt: row.created_at,
                tradeID: row.trade_id,
                postID: nil,
                reelID: id,
                achievementID: nil,
                caption: row.caption,
                mediaURL: row.thumbnail_url ?? row.video_url,
                profiles: row.profiles?.profile
            )
        }
    }

    private func fetchAchievementFeedBatch(
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String],
        page: PageRequest
    ) async throws -> [FeedItem] {
        guard let query = feedPageQuery(
            select: Self.achievementFeedSelect,
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page,
            extra: [URLQueryItem(name: "achievements.is_public", value: "eq.true")]
        ) else { return [] }
        let rows: [FeedDTO.AchievementFeedRow] = try await supabase.database.select(
            FeedDTO.AchievementFeedRow.self,
            from: "achievement_posts",
            query: query
        )
        return rows.compactMap { row -> FeedItem? in
            guard let id = row.id, let author = row.user_id else { return nil }
            let achievementID = row.achievement_id
                ?? row.achievements?.achievement?.id
            return makeFeedItem(
                id: id,
                kind: .achievement,
                author: author,
                createdAt: row.created_at,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                achievementID: achievementID,
                caption: row.achievements?.achievement?.title,
                mediaURL: row.achievements?.achievement?.image_url,
                profiles: row.profiles?.profile
            )
        }
    }

    private func makeFeedItem(
        id: String,
        kind: FeedItemKind,
        author: String,
        createdAt: String?,
        tradeID: String?,
        postID: String?,
        reelID: String?,
        achievementID: String?,
        caption: String?,
        mediaURL: String?,
        profiles: FeedDTO.EmbeddedAuthor?
    ) -> FeedItem {
        let username = profiles?.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = profiles?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatar = profiles?.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeedItem(
            id: id,
            kind: kind,
            authorProfileID: ProfileID(author),
            createdAt: ISO8601.date(from: createdAt) ?? Date(),
            tradeID: tradeID.flatMap { $0.isEmpty ? nil : TradeID($0) },
            postID: postID.map { PostID($0) },
            reelID: reelID.map { ReelID($0) },
            storyID: nil,
            achievementID: achievementID.map { AchievementID($0) },
            caption: caption,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            authorUsername: (username?.isEmpty == false) ? username : nil,
            authorDisplayName: {
                if let name, !name.isEmpty { return name }
                if let username, !username.isEmpty { return username }
                return nil
            }(),
            authorAvatarURL: (avatar?.isEmpty == false) ? avatar : nil,
            mediaURL: (media?.isEmpty == false) ? media : nil
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

    func posts(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        let rows: [FeedDTO.Post] = try await supabase.database.select(
            FeedDTO.Post.self,
            from: "posts",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
            ]
        )
        let items = rows.compactMap { try? mapPost($0) }
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
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
        let row: ProfileReelRow = try await supabase.database.selectOne(
            ProfileReelRow.self,
            from: "reels",
            query: [
                SupabaseQuery.select(Self.reelRowSelect),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        guard let mapped = mapReel(row) else {
            throw AppError.domain(.notFound(entity: "reel", id: id.rawValue))
        }
        return mapped
    }

    func reels(authoredBy profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Reel> {
        let rows: [ProfileReelRow] = try await supabase.database.select(
            ProfileReelRow.self,
            from: "reels",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select(Self.reelRowSelect),
                SupabaseQuery.eq("user_id", profileID.rawValue),
            ]
        )
        let items = rows.compactMap(mapReel)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func profileReels(for profileID: ProfileID) async throws -> [Reel] {
        // Mirror web `fetchUserProfileReels`: embed query → filter; fallback hydrate.
        let rows: [ProfileReelRow]
        do {
            rows = try await supabase.database.select(
                ProfileReelRow.self,
                from: "reels",
                query: [
                    SupabaseQuery.select(Self.profileReelsSelect),
                    SupabaseQuery.eq("user_id", profileID.rawValue),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                ]
            )
        } catch {
            AppLog.networking.error(
                "Profile reels embed failed — falling back — \(String(describing: error), privacy: .public)"
            )
            let fallback: [ProfileReelRow] = try await supabase.database.select(
                ProfileReelRow.self,
                from: "reels",
                query: [
                    SupabaseQuery.select(Self.reelRowSelect),
                    SupabaseQuery.eq("user_id", profileID.rawValue),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                ]
            )
            rows = try await hydrateReelsWithTrades(fallback)
        }

        return rows
            .filter(Self.isReelListedOnProfile)
            .compactMap { row in
                let mapped = mapReel(row)
                if mapped == nil {
                    AppLog.networking.error(
                        "Skipping reel \(row.id ?? "unknown", privacy: .public) — mapping failed"
                    )
                }
                return mapped
            }
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
        let row: ProfileReelRow = try await supabase.database.insert(
            body,
            into: "reels",
            returning: ProfileReelRow.self
        )
        return mapReel(row) ?? reel
    }

    // MARK: - Profile reel DTOs (web `ReelRow` + trade embed)

    private struct ProfileReelRow: Codable {
        var id: String?
        var user_id: String?
        var caption: String?
        var video_url: String?
        var thumbnail_url: String?
        var duration_seconds: Int?
        var visibility: String?
        var trade_id: String?
        var kind: String?
        var created_at: String?
        var updated_at: String?
        /// PostgREST may return object or single-element array for many-to-one embeds.
        var trades: TradeJoinBox?
    }

    private struct ReelTradeJoin: Codable {
        var id: String?
        var public_description: String?
        var is_public: Bool?
        var ticker: String?
        var direction: String?
        var pnl: FlexibleNumber?
        var rr: FlexibleNumber?
    }

    /// Decodes either a single embedded trade object or an array.
    private struct TradeJoinBox: Codable {
        var trades: [ReelTradeJoin]

        init(trades: [ReelTradeJoin]) {
            self.trades = trades
        }

        init(from decoder: Decoder) throws {
            if let single = try? ReelTradeJoin(from: decoder) {
                trades = [single]
                return
            }
            trades = try [ReelTradeJoin](from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            try trades.encode(to: encoder)
        }
    }

    private func mapReel(_ row: ProfileReelRow) -> Reel? {
        guard let reelID = row.id,
              let author = row.user_id,
              let video = row.video_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !video.isEmpty else {
            return nil
        }
        let thumb = row.thumbnail_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibility: ContentVisibility = (row.visibility?.lowercased() == "private") ? .private : .public
        let caption: String? = {
            if let tradeCaption = resolveTradeCaption(row) { return tradeCaption }
            let raw = row.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }()
        return Reel(
            id: ReelID(reelID),
            authorProfileID: ProfileID(author),
            video: MediaReference(id: video, kind: .video, altText: nil),
            thumbnail: thumb.flatMap { $0.isEmpty ? nil : MediaReference(id: $0, kind: .image, altText: nil) },
            caption: caption,
            visibility: visibility,
            linkedTradeID: row.trade_id.map { TradeID($0) },
            durationSeconds: row.duration_seconds,
            createdAt: ISO8601.date(from: row.created_at) ?? Date()
        )
    }

    /// Web `isReelListedOnProfile`.
    private static func isReelListedOnProfile(_ row: ProfileReelRow) -> Bool {
        let tradeID = row.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tradeID.isEmpty {
            return resolveTradeJoin(row)?.is_public == true
        }
        return true
    }

    private static func resolveTradeJoin(_ row: ProfileReelRow) -> ReelTradeJoin? {
        row.trades?.trades.first
    }

    private func resolveTradeCaption(_ row: ProfileReelRow) -> String? {
        let tradeID = row.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tradeID.isEmpty else { return nil }
        let raw = Self.resolveTradeJoin(row)?.public_description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private func hydrateReelsWithTrades(_ rows: [ProfileReelRow]) async throws -> [ProfileReelRow] {
        let tradeIDs = Array(
            Set(
                rows.compactMap { row -> String? in
                    let id = row.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return id.isEmpty ? nil : id
                }
            )
        )
        guard !tradeIDs.isEmpty else { return rows }

        struct TradeRow: Codable {
            var id: String?
            var public_description: String?
            var is_public: Bool?
            var ticker: String?
            var direction: String?
            var pnl: FlexibleNumber?
            var rr: FlexibleNumber?
        }

        // PostgREST `in` filter — same as web hydrate.
        let joined = tradeIDs.map { "\"\($0)\"" }.joined(separator: ",")
        let trades: [TradeRow] = try await supabase.database.select(
            TradeRow.self,
            from: "trades",
            query: [
                SupabaseQuery.select(Self.reelTradeJoinSelect),
                URLQueryItem(name: "id", value: "in.(\(joined))"),
            ]
        )
        let byID = Dictionary(uniqueKeysWithValues: trades.compactMap { row -> (String, ReelTradeJoin)? in
            guard let id = row.id else { return nil }
            return (
                id,
                ReelTradeJoin(
                    id: row.id,
                    public_description: row.public_description,
                    is_public: row.is_public,
                    ticker: row.ticker,
                    direction: row.direction,
                    pnl: row.pnl,
                    rr: row.rr
                )
            )
        })

        return rows.map { row in
            var copy = row
            if let tradeID = row.trade_id, let join = byID[tradeID] {
                copy.trades = TradeJoinBox(trades: [join])
            }
            return copy
        }
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
            isPinned: false,
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
