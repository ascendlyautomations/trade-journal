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

    /// Feed trade cards, profiles + compact trade embed so list hydrate needs no per-row trade SELECT.
    private static let tradeFeedSelect =
        "id,user_id,trade_id,created_at,image_url,image_crop,profiles(username,avatar_url,name),trades(id,user_id,ticker,direction,pnl,rr,contracts,session,public_description,is_public,image_url,image_crop,created_at,entry_time,exit_time,entry_price,exit_price,account_type,mode)"

    /// Web `FEED_PROFILE_POSTS_SELECT` (core columns + profiles embed).
    private static let profileFeedSelect =
        "id,user_id,content,image_url,image_crop,created_at,room_id,room_name,room_logo,room_description,profiles(username,avatar_url,name)"

    /// Web `FEED_REELS_SELECT` without trade embed (list identity + profiles).
    private static let reelFeedSelect =
        "id,user_id,caption,video_url,thumbnail_url,duration_seconds,visibility,trade_id,kind,created_at,profiles(username,avatar_url,name)"

    /// Web `FEED_ACHIEVEMENT_POSTS_SELECT` (identity + public achievement + profiles).
    private static let achievementFeedSelect =
        "id,user_id,achievement_id,created_at,achievements(id,title,description,achievement_type,badge_key,tier,value_text,value_numeric,currency,image_url,image_crop,achieved_at,is_public,is_featured,category,firm,metadata),profiles(username,avatar_url,name)"

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.session = session
    }

    /// Web `topUpMergedFeedBuffer` first page, trades + profile_posts + reels + achievement_posts.
    func feed(
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        page: PageRequest
    ) async throws -> FeedPageResult {
        let viewerID = await session.currentUserID?.rawValue
        let followingIDs = try await fetchFollowingIDs(viewerID: viewerID)

        if scope == .following, followingIDs.isEmpty {
            return FeedPageResult(items: [], nextCursor: nil, embeddedTrades: [])
        }

        if contentFilter == .clips {
            let reels = try await fetchReelFeedBatch(
                scope: scope,
                viewerID: viewerID,
                followingIDs: followingIDs,
                page: page
            )
            let blockPeers = try await fetchActiveBlockPeerIDs()
            var merged = reels
            if !blockPeers.isEmpty {
                merged = merged.filter { !blockPeers.contains($0.authorProfileID) }
            }
            merged.sort { $0.createdAt > $1.createdAt }
            let limited = Array(merged.prefix(page.limit))
            let next = limited.count >= page.limit
                ? ISO8601.string(from: limited.last?.createdAt ?? Date())
                : nil
            return FeedPageResult(items: limited, nextCursor: next, embeddedTrades: [])
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

        let (tradePage, posts, reels, achievements) = try await (
            tradeBatch, profileBatch, reelBatch, achievementBatch
        )

        // Web `dedupeFeedItems`, skip trade-attached reels (they render on the trade card).
        let standaloneReels = reels.filter { item in
            guard let tradeID = item.tradeID?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return true }
            return tradeID.isEmpty
        }

        var merged = tradePage.items + posts + standaloneReels + achievements
        merged.sort { $0.createdAt > $1.createdAt }

        let blockPeers = try await fetchActiveBlockPeerIDs()
        if !blockPeers.isEmpty {
            merged = merged.filter { !blockPeers.contains($0.authorProfileID) }
        }

        let limited = Array(merged.prefix(page.limit))
        let next = limited.count >= page.limit
            ? ISO8601.string(from: limited.last?.createdAt ?? Date())
            : nil
        let limitedTradeIDs = Set(limited.compactMap(\.tradeID))
        let embeds = tradePage.embeddedTrades.filter { limitedTradeIDs.contains($0.id) }
        return FeedPageResult(items: limited, nextCursor: next, embeddedTrades: embeds)
    }

    // MARK: - Web feed batches (`lib/feedContent.ts`)

    private func fetchActiveBlockPeerIDs() async throws -> Set<ProfileID> {
        guard await session.currentUserID != nil else { return [] }
        let data = try await supabase.database.rpcData(
            functionName: "get_active_block_peer_ids",
            parametersJSON: Data("{}".utf8)
        )
        if let ids = try? JSONDecoder().decode([String].self, from: data) {
            return Set(ids.map { ProfileID($0) })
        }
        return []
    }

    private func fetchFollowingIDs(viewerID: String?) async throws -> [String] {
        guard let viewerID, !viewerID.isEmpty else { return [] }
        // Memory → disk → one edge SELECT. Stories/Feed/Explore share SessionFollowingStore.
        if let cached = await SessionFollowingStore.shared.cached(viewerID: viewerID) {
            return Array(cached).sorted()
        }
        if let disk = RelationshipFollowingPersistence.loadComplete(for: ProfileID(viewerID)) {
            await SessionFollowingStore.shared.seedComplete(viewerID: viewerID, ids: Set(disk))
            return disk.sorted()
        }
        let database = supabase.database
        return try await SessionFollowingStore.shared.followingIDs(viewerID: viewerID) {
            struct Row: Codable { var following_id: String? }
            let rows: [Row] = try await database.select(
                Row.self,
                from: "followers",
                query: [
                    SupabaseQuery.select("following_id"),
                    SupabaseQuery.eq("follower_id", viewerID),
                ]
            )
            let ids = rows.compactMap { row -> String? in
                let id = row.following_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return id.isEmpty ? nil : id
            }
            let viewer = ProfileID(viewerID)
            let generation = RelationshipWriteGeneration.bump(viewerID: viewer)
            RelationshipFollowingPersistence.saveComplete(ids: ids, viewerID: viewer, generation: generation)
            return ids
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

    private struct TradeFeedBatch: Sendable {
        var items: [FeedItem]
        var embeddedTrades: [Trade]
    }

    private func fetchTradeFeedBatch(
        scope: FeedScope,
        viewerID: String?,
        followingIDs: [String],
        page: PageRequest
    ) async throws -> TradeFeedBatch {
        guard let query = feedPageQuery(
            select: Self.tradeFeedSelect,
            scope: scope,
            viewerID: viewerID,
            followingIDs: followingIDs,
            page: page
        ) else {
            return TradeFeedBatch(items: [], embeddedTrades: [])
        }
        let rows: [FeedDTO.TradeFeedRow] = try await supabase.database.select(
            FeedDTO.TradeFeedRow.self,
            from: "posts",
            query: query
        )
        var embeds: [Trade] = []
        let items: [FeedItem] = rows.compactMap { row in
            guard let id = row.id, let author = row.user_id else { return nil }
            if var dto = row.trades?.trade {
                if dto.image_crop == nil {
                    dto.image_crop = row.image_crop
                }
                if let trade = try? TradeMapper.mapToDomain(dto) {
                    embeds.append(trade)
                }
            }
            // Web `normalizeTradeFeedItem`, posts table rows are trade feed cards.
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
        return TradeFeedBatch(items: items, embeddedTrades: embeds)
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
            var item = makeFeedItem(
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
                imageCrop: row.image_crop,
                profiles: row.profiles?.profile
            )
            item.roomShare = RoomShareAttachment.parsed(
                roomID: row.room_id,
                name: row.room_name,
                logoURL: row.room_logo,
                description: row.room_description
            )
            return item
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
                imageCrop: row.achievements?.achievement?.image_crop,
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
        imageCrop: ContentImagePresentation? = nil,
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
            mediaURL: (media?.isEmpty == false) ? media : nil,
            imageCrop: imageCrop
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
        await ActivityNotificationClient(transport: supabase.transport)
            .notifyComment(commentID: mapped.id.rawValue)
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
            let viewerID = await session.currentUserID?.rawValue
            if viewerID != item.authorProfileID.rawValue {
                await ActivityNotificationClient(transport: supabase.transport)
                    .notifyLike(.profilePost(profilePostId: postID.rawValue))
            }
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

    /// Web `fetchActiveStoriesForUserIds`, following + self, `image_url`, client 24h window.
    func allActiveStories(for viewer: ProfileID) async throws -> [Story] {
        try await fetchActiveStories(viewer: viewer)
    }

    func stories(for viewer: ProfileID) async throws -> [Story] {
        let active = try await fetchActiveStories(viewer: viewer)
        let strip = ActiveStorySemantics.stripStories(from: active, viewerID: viewer)
        #if DEBUG
        StoriesLoadProbe.record(
            stage: "filtered",
            detail: "active=\(active.count) strip=\(strip.count)"
        )
        #endif
        return strip
    }

    private func fetchActiveStories(viewer: ProfileID) async throws -> [Story] {
        if await session.currentUserID != nil,
           let rpcStories = try await fetchActiveStoriesViaRPC()
        {
            return rpcStories
        }
        return try await fetchActiveStoriesViaREST(viewer: viewer)
    }

    /// `rpc_v1_viewer_active_stories`: following graph + `viewer_has_seen` from `story_views`.
    private func fetchActiveStoriesViaRPC() async throws -> [Story]? {
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_viewer_active_stories",
            parametersJSON: Data("{}".utf8)
        )
        let previews = try JSONDecoder().decode([FeedStoryPreviewV1].self, from: data)
        let mapped = StoryBootstrapMapping.map(previews)
        let pathByStoryID = Dictionary(
            uniqueKeysWithValues: previews.map { ($0.id, $0.storage_path) }
        )
        return await signHydratedActiveStories(mapped, storagePathByStoryID: pathByStoryID)
    }

    private func fetchActiveStoriesViaREST(viewer: ProfileID) async throws -> [Story] {
        struct Row: Codable {
            var id: String?
            var user_id: String?
            var image_url: String?
            var storage_path: String?
            var created_at: String?
        }

        let followingIDs = try await fetchFollowingIDs(viewerID: viewer.rawValue)
        var candidateIDs = followingIDs
        if !candidateIDs.contains(viewer.rawValue) {
            candidateIDs.append(viewer.rawValue)
        }
        #if DEBUG
        StoriesLoadProbe.reset()
        StoriesLoadProbe.record(
            stage: "candidates",
            detail: "following=\(followingIDs.count) candidates=\(candidateIDs.count)"
        )
        #endif
        guard !candidateIDs.isEmpty else {
            #if DEBUG
            StoriesLoadProbe.record(stage: "supabase", detail: "skipped, no candidate user ids")
            #endif
            return []
        }

        // Same select as web `ACTIVE_STORIES_SELECT`. Expired rows stay out even before cleanup.
        let cutoff = ISO8601.string(from: Date().addingTimeInterval(-ActiveStorySemantics.window))
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "stories",
            query: [
                SupabaseQuery.select("id,user_id,image_url,storage_path,created_at"),
                SupabaseQuery.isIn("user_id", candidateIDs),
                URLQueryItem(name: "created_at", value: "gt.\(cutoff)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        #if DEBUG
        StoriesLoadProbe.record(stage: "supabase", detail: "rows=\(rows.count)")
        #endif

        var parseFailures = 0
        let mapped: [Story] = rows.compactMap { row in
            guard let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
                  let author = row.user_id?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty
            else { return nil }
            let imageURL = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let storagePath = row.storage_path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mediaSeed = !imageURL.isEmpty ? imageURL : storagePath
            guard !mediaSeed.isEmpty else { return nil }
            // Web `isStoryActive`: invalid `created_at` → inactive (never invent distantPast).
            guard let created = ISO8601.date(from: row.created_at) else {
                parseFailures += 1
                return nil
            }
            let kind = Self.storyMediaKind(forPublicURL: storagePath.isEmpty ? mediaSeed : storagePath)
            return Story(
                id: StoryID(id),
                authorProfileID: ProfileID(author),
                media: MediaReference(id: mediaSeed, kind: kind, altText: nil),
                expiresAt: created.addingTimeInterval(ActiveStorySemantics.window),
                createdAt: created,
                viewerHasSeen: false
            )
        }
        #if DEBUG
        StoriesLoadProbe.record(
            stage: "decoded",
            detail: "mapped=\(mapped.count) parseFailures=\(parseFailures)"
        )
        #endif

        let pathByStoryID = Dictionary(
            uniqueKeysWithValues: rows.compactMap { row -> (String, String?)? in
                guard let id = row.id else { return nil }
                return (id, row.storage_path)
            }
        )
        return await signHydratedActiveStories(mapped, storagePathByStoryID: pathByStoryID)
    }

    private func signHydratedActiveStories(
        _ mapped: [Story],
        storagePathByStoryID: [String: String?]
    ) async -> [Story] {
        let now = Date()
        let active = ActiveStorySemantics.filterActive(mapped, now: now)
        var signed: [Story] = []
        for story in active {
            let kind = story.media.kind
            let rowPath = storagePathByStoryID[story.id.rawValue] ?? nil
            let resolvedPath = StoryStoragePathSupport.resolve(
                storagePath: rowPath,
                imageURL: story.media.id
            )
            if let media = await StorySignedMediaResolver.shared.signedMediaReference(
                storagePath: resolvedPath,
                imageURL: story.media.id,
                isVideo: kind == .video
            ) {
                var copy = story
                copy.media = media
                signed.append(copy)
                StoryDebug.logMediaRef(
                    "fetchActiveStories.signed",
                    storyID: story.id.rawValue,
                    mediaID: media.id,
                    kind: kind.rawValue
                )
            } else {
                signed.append(story)
                StoryDebug.logMediaRef(
                    "fetchActiveStories.unsigned",
                    storyID: story.id.rawValue,
                    mediaID: story.media.id,
                    kind: kind.rawValue
                )
            }
        }
        #if DEBUG
        if mapped.count > 0, active.isEmpty {
            let ages = mapped.map { Int(now.timeIntervalSince($0.createdAt)) }
            StoriesLoadProbe.record(
                stage: "filtered",
                detail: "active=0 agesSec=\(ages) window=\(Int(ActiveStorySemantics.window))"
            )
        }
        #endif
        return signed
    }

    func story(id: StoryID) async throws -> Story? {
        guard let loaded = try await storyForViewer(id: id) else {
            StoryDebug.log("story(id)", "story=\(id.rawValue) rpc=nil")
            return nil
        }
        let active = ActiveStorySemantics.isActive(createdAt: loaded.createdAt)
        guard active else {
            StoryDebug.log(
                "story(id)",
                "story=\(id.rawValue) rejected inactive created=\(loaded.createdAt)"
            )
            return nil
        }
        return loaded
    }

    func storyForViewer(id: StoryID) async throws -> Story? {
        struct Args: Encodable { var p_story_id: String }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_story_for_viewer",
            parametersJSON: try JSONEncoder().encode(Args(p_story_id: id.rawValue))
        )
        let isNull = data.isEmpty || data == Data("null".utf8)
        StoryDebug.log(
            "rpc_v1_story_for_viewer",
            "story=\(id.rawValue) bytes=\(data.count) null=\(isNull)"
        )
        guard !isNull else { return nil }
        do {
            let mapped = try await mapStoryRPCPayload(data)
            StoryDebug.log(
                "rpc_v1_story_for_viewer.mapped",
                "story=\(id.rawValue) ok=\(mapped != nil)"
            )
            return mapped
        } catch {
            StoryDebug.log(
                "rpc_v1_story_for_viewer.decode",
                "story=\(id.rawValue) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func archivedStories(limit: Int = 60, offset: Int = 0) async throws -> [Story] {
        struct Args: Encodable {
            var p_limit: Int
            var p_offset: Int
        }
        struct Payload: Decodable {
            var stories: [StoryRPCRowFull]?
        }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_owner_story_archive",
            parametersJSON: try JSONEncoder().encode(Args(p_limit: limit, p_offset: offset))
        )
        let decoder = JSONDecoder()
        let payload = try decoder.decode(Payload.self, from: data)
        var stories: [Story] = []
        for row in payload.stories ?? [] {
            if let story = await mapStoryRow(row) {
                stories.append(story)
            }
        }
        return stories
    }

    func storyDmMediaAccess(id: StoryID) async throws -> StoryDmMediaAccess {
        struct Args: Encodable { var p_story_id: String }
        struct Payload: Decodable {
            var allowed: Bool?
            var reason: String?
            var id: String?
            var user_id: String?
            var created_at: String?
            var storage_path: String?
            var image_url: String?
        }
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_story_dm_media_access",
            parametersJSON: try JSONEncoder().encode(Args(p_story_id: id.rawValue))
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return StoryDmMediaAccess(
            allowed: payload.allowed == true,
            reason: payload.reason ?? "unavailable",
            storyID: payload.id.flatMap { StoryID($0) },
            ownerID: payload.user_id.flatMap { ProfileID($0) },
            createdAt: payload.created_at.flatMap { ISO8601.date(from: $0) },
            storagePath: payload.storage_path,
            imageURL: payload.image_url
        )
    }

    private struct StoryRPCRowFull: Decodable {
        var id: String?
        var user_id: String?
        var image_url: String?
        var storage_path: String?
        var resolved_storage_path: String?
        var created_at: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = Self.decodeFlexibleString(container, key: .id)
            user_id = Self.decodeFlexibleString(container, key: .user_id)
            image_url = try container.decodeIfPresent(String.self, forKey: .image_url)
            storage_path = try container.decodeIfPresent(String.self, forKey: .storage_path)
            resolved_storage_path = try container.decodeIfPresent(String.self, forKey: .resolved_storage_path)
            created_at = Self.decodeFlexibleString(container, key: .created_at)
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case user_id
            case image_url
            case storage_path
            case resolved_storage_path
            case created_at
        }

        private static func decodeFlexibleString(
            _ container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys
        ) -> String? {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let value = try? container.decodeIfPresent(UUID.self, forKey: key) {
                return value.uuidString
            }
            return nil
        }
    }

    private func mapStoryRPCPayload(_ data: Data) async throws -> Story? {
        let row = try JSONDecoder().decode(StoryRPCRowFull.self, from: data)
        return await mapStoryRow(row)
    }

    private func mapStoryRow(_ row: StoryRPCRowFull) async -> Story? {
        guard let storyID = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !storyID.isEmpty,
              let author = row.user_id?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty,
              let created = row.created_at.flatMap({ ISO8601.date(from: $0) })
        else {
            StoryDebug.log(
                "mapStoryRow.invalidRow",
                "id=\(row.id ?? "nil") user=\(row.user_id ?? "nil") created=\(row.created_at ?? "nil")"
            )
            return nil
        }

        let path = row.resolved_storage_path ?? row.storage_path
        let imageURL = row.image_url
        let kind = Self.storyMediaKind(forPublicURL: path ?? imageURL ?? "")
        let active = ActiveStorySemantics.isActive(createdAt: created)
        StoryDebug.log(
            "mapStoryRow.row",
            """
            story=\(storyID) storage_path=\(row.storage_path ?? "nil") \
            resolved=\(row.resolved_storage_path ?? "nil") image_url=\(imageURL ?? "nil") \
            active24h=\(active) created=\(row.created_at ?? "nil")
            """
        )
        let media: MediaReference
        if let signed = await StorySignedMediaResolver.shared.signedMediaReference(
            storagePath: path,
            imageURL: imageURL,
            isVideo: kind == .video
        ) {
            media = signed
        } else if let fallback = await fallbackStoryMediaReference(
            storagePath: path,
            imageURL: imageURL,
            kind: kind
        ) {
            StoryDebug.log("mapStoryRow.signFailed", "story=\(storyID) usingUnsignedFallback")
            media = fallback
        } else {
            StoryDebug.log("mapStoryRow.signFailed", "story=\(storyID) noMedia")
            return nil
        }

        return Story(
            id: StoryID(storyID),
            authorProfileID: ProfileID(author),
            media: media,
            expiresAt: created.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: created,
            viewerHasSeen: false
        )
    }

    func createStory(userID: ProfileID, imageURL: String) async throws -> Story {
        try await createStory(userID: userID, imageURL: imageURL, textOverlays: [])
    }

    func createStory(
        userID: ProfileID,
        imageURL: String,
        textOverlays: [StoryTextOverlayRecord]
    ) async throws -> Story {
        struct PlainBody: Encodable {
            var user_id: String
            var image_url: String
            var storage_path: String
        }
        struct OverlayBody: Encodable {
            var user_id: String
            var image_url: String
            var storage_path: String
            var text_overlays: [StoryTextOverlayRecord]
        }
        struct Row: Codable {
            var id: String?
            var user_id: String?
            var image_url: String?
            var created_at: String?
        }

        let trimmedURL = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw AppError.unknown(message: "Missing story image")
        }
        let objectPath = StoryStoragePathSupport.resolve(storagePath: nil, imageURL: trimmedURL) ?? trimmedURL

        let overlays = textOverlays.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let row: Row
        if overlays.isEmpty {
            row = try await supabase.database.insert(
                PlainBody(
                    user_id: userID.rawValue,
                    image_url: objectPath,
                    storage_path: objectPath
                ),
                into: "stories",
                returning: Row.self
            )
        } else {
            row = try await supabase.database.insert(
                OverlayBody(
                    user_id: userID.rawValue,
                    image_url: objectPath,
                    storage_path: objectPath,
                    text_overlays: overlays
                ),
                into: "stories",
                returning: Row.self
            )
        }

        guard let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let author = row.user_id?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty,
              let media = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines), !media.isEmpty,
              let created = ISO8601.date(from: row.created_at)
        else {
            throw AppError.unknown(message: "Story couldn't be published. Please try again.")
        }

        StoryDebug.log(
            "createStory.inserted",
            "story=\(id) image_url=\(media) storage_path=\(objectPath)"
        )

        return Story(
            id: StoryID(id),
            authorProfileID: ProfileID(author),
            media: MediaReference(
                id: media,
                kind: Self.storyMediaKind(forPublicURL: media),
                altText: nil
            ),
            expiresAt: created.addingTimeInterval(ActiveStorySemantics.window),
            createdAt: created,
            viewerHasSeen: false
        )
    }

    func storyTextOverlays(id: StoryID) async throws -> [StoryTextOverlayRecord] {
        struct Row: Codable {
            var text_overlays: [StoryTextOverlayRecord]?
        }

        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "stories",
            query: [
                SupabaseQuery.select("text_overlays"),
                SupabaseQuery.eq("id", id.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first?.text_overlays ?? []
    }

    private static func storyMediaKind(forPublicURL url: String) -> MediaKind {
        let path = url.lowercased()
        for ext in [".mp4", ".mov", ".m4v", ".webm"] where path.hasSuffix(ext) {
            return .video
        }
        return .image
    }

    private func fallbackStoryMediaReference(
        storagePath: String?,
        imageURL: String?,
        kind: MediaKind
    ) async -> MediaReference? {
        if let url = await StorySignedMediaResolver.shared.playableURL(
            storagePath: storagePath,
            imageURL: imageURL
        ) {
            return MediaReference(id: url.absoluteString, kind: kind, altText: nil)
        }
        let trimmedPath = storagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPath.isEmpty {
            return MediaReference(id: trimmedPath, kind: kind, altText: nil)
        }
        let trimmedURL = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedURL.isEmpty else { return nil }
        return MediaReference(id: trimmedURL, kind: kind, altText: nil)
    }

    func deleteStory(id: StoryID) async throws {
        let media = try? await mediaURLs(
            from: "stories",
            id: id.rawValue,
            columns: "image_url"
        )
        try await supabase.database.delete(
            from: "stories",
            query: [SupabaseQuery.eq("id", id.rawValue)]
        )
        let storyOwned = (media ?? []).filter { url in
            OwnedMediaStorageCleanup.location(fromPublicURL: url)?.bucket == StorageBucket.stories.rawValue
        }
        var removable: [String?] = []
        for url in storyOwned {
            guard let url, !(await storyMediaURLIsShared(url)) else { continue }
            removable.append(url)
        }
        await OwnedMediaStorageCleanup.removePublicObjects(
            urls: removable,
            storage: supabase.storage
        )
    }

    func storyInsights(id: StoryID) async throws -> StoryInsights {
        struct Args: Encodable { var p_story_id: String }
        let args = Args(p_story_id: id.rawValue)
        let data = try await supabase.database.rpcData(
            functionName: "rpc_v1_story_insights",
            parametersJSON: try JSONEncoder().encode(args)
        )
        return try StoryInsightsMapper.decode(from: data)
    }

    func recordStoryView(id: StoryID) async throws {
        guard await session.currentUserID != nil else { return }
        struct Args: Encodable { var p_story_id: String }
        let args = Args(p_story_id: id.rawValue)
        _ = try await supabase.database.rpcData(
            functionName: "rpc_v1_story_record_view",
            parametersJSON: try JSONEncoder().encode(args)
        )
    }

    /// True when another story, post, clip, or trade still points at this URL.
    /// A failed lookup is treated as shared so cleanup cannot delete someone else's media.
    private func storyMediaURLIsShared(_ url: String) async -> Bool {
        if await mediaURLExists(in: "stories", column: "image_url", url: url) { return true }
        if await mediaURLExists(in: "profile_posts", column: "image_url", url: url) { return true }
        if await mediaURLExists(in: "posts", column: "image_url", url: url) { return true }
        if await mediaURLExists(in: "reels", column: "video_url", url: url) { return true }
        if await mediaURLExists(in: "reels", column: "thumbnail_url", url: url) { return true }
        if await mediaURLExists(in: "trades", column: "image_url", url: url) { return true }
        return false
    }

    private func mediaURLExists(in table: String, column: String, url: String) async -> Bool {
        struct Row: Decodable, Sendable { var id: String? }
        do {
            let rows: [Row] = try await supabase.database.select(
                Row.self,
                from: table,
                query: [
                    SupabaseQuery.select("id"),
                    SupabaseQuery.eq(column, url),
                    URLQueryItem(name: "limit", value: "1"),
                ]
            )
            return !rows.isEmpty
        } catch {
            return true
        }
    }

    func reel(id: ReelID) async throws -> ReelLoadResult {
        let viewerID = await session.currentUserID.map { ProfileID($0.rawValue) }
        let row: ProfileReelRow
        do {
            row = try await supabase.database.selectOne(
                ProfileReelRow.self,
                from: "reels",
                query: [
                    SupabaseQuery.select(Self.profileReelsSelect),
                    SupabaseQuery.eq("id", id.rawValue),
                ]
            )
        } catch {
            AppLog.networking.error(
                "Reel embed load failed, falling back, \(String(describing: error), privacy: .public)"
            )
            row = try await supabase.database.selectOne(
                ProfileReelRow.self,
                from: "reels",
                query: [
                    SupabaseQuery.select(Self.reelRowSelect),
                    SupabaseQuery.eq("id", id.rawValue),
                ]
            )
        }
        guard let mapped = mapReel(row) else {
            throw AppError.domain(.notFound(entity: "reel", id: id.rawValue))
        }
        let embeddedTrade = mapEmbeddedTrade(from: row, viewerID: viewerID)
        return ReelLoadResult(reel: mapped, embeddedTrade: embeddedTrade)
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

    func profileReels(for profileID: ProfileID) async throws -> ProfileReelsResult {
        // Mirror web `fetchUserProfileReels`: embed query → filter; fallback hydrate.
        try await RepositoryRequestFlight.shared.coalesce(
            key: "feed.profileReels:\(profileID.rawValue)",
            resource: "feed.profileReels"
        ) { [self] in
            try await self.fetchProfileReelsUncoalesced(for: profileID)
        }
    }

    func reels(linkedToTradeIDs tradeIDs: [TradeID], ownerID: ProfileID) async throws -> [Reel] {
        let normalized = Array(Set(tradeIDs.map(\.rawValue)))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return [] }
        let flightKey = "feed.reelsByTradeIds:\(ownerID.rawValue):\(normalized.sorted().joined(separator: ","))"
        return try await RepositoryRequestFlight.shared.coalesce(
            key: flightKey,
            resource: "feed.reelsByTradeIds"
        ) { [self] in
            try await self.fetchReelsByTradeIDsUncoalesced(normalized, ownerID: ownerID)
        }
    }

    private func fetchReelsByTradeIDsUncoalesced(
        _ tradeIDStrings: [String],
        ownerID: ProfileID
    ) async throws -> [Reel] {
        let batchSize = 40
        var reels: [Reel] = []
        reels.reserveCapacity(tradeIDStrings.count)
        var index = tradeIDStrings.startIndex
        while index < tradeIDStrings.endIndex {
            let end = tradeIDStrings.index(index, offsetBy: batchSize, limitedBy: tradeIDStrings.endIndex)
                ?? tradeIDStrings.endIndex
            let chunk = Array(tradeIDStrings[index..<end])
            let rows: [ProfileReelRow] = try await supabase.database.select(
                ProfileReelRow.self,
                from: "reels",
                query: [
                    SupabaseQuery.select(Self.reelRowSelect),
                    SupabaseQuery.eq("user_id", ownerID.rawValue),
                    SupabaseQuery.isIn("trade_id", chunk),
                ]
            )
            reels.append(contentsOf: rows.compactMap(mapReel))
            index = end
        }
        return reels
    }

    private func fetchProfileReelsUncoalesced(for profileID: ProfileID) async throws -> ProfileReelsResult {
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
                "Profile reels embed failed, falling back, \(String(describing: error), privacy: .public)"
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

        let reels = rows
            .filter(Self.isReelListedOnProfile)
            .compactMap { row in
                let mapped = mapReel(row)
                if mapped == nil {
                    AppLog.networking.error(
                        "Skipping reel \(row.id ?? "unknown", privacy: .public), mapping failed"
                    )
                }
                return mapped
            }
        let embeddedTrades = rows.compactMap { mapEmbeddedTrade(from: $0) }
        return ProfileReelsResult(reels: reels, embeddedTrades: embeddedTrades)
    }

    func createReel(_ reel: Reel) async throws -> Reel {
        struct Body: Encodable {
            var user_id: String
            var video_url: String
            var thumbnail_url: String
            var caption: String?
            var trade_id: String?
            var duration_seconds: Int?
            var visibility: String
            var kind: String?
        }
        // thumbnail_url is NOT NULL, fall back to video URL (web publishReel).
        let thumb = reel.thumbnail?.id ?? reel.video.id

        var visibility = reel.visibility == .private ? "private" : "public"
        if let tradeID = reel.linkedTradeID {
            guard try await tradeOwnedByAuthor(tradeID: tradeID, authorID: reel.authorProfileID) else {
                throw AppError.domain(.notFound(entity: "trade", id: tradeID.rawValue))
            }
            let tradeIsPublic = try await tradeIsPublicFlag(tradeID: tradeID)
            visibility = tradeIsPublic ? "public" : "private"
        }
        let caption = ReelPublishPipeline.normalizedCaption(reel.caption ?? "")

        let body = Body(
            user_id: reel.authorProfileID.rawValue,
            video_url: reel.video.id,
            thumbnail_url: thumb,
            caption: caption,
            trade_id: reel.linkedTradeID?.rawValue,
            duration_seconds: reel.durationSeconds,
            visibility: visibility,
            kind: nil
        )
        let row: ProfileReelRow = try await supabase.database.insert(
            body,
            into: "reels",
            query: [SupabaseQuery.select(Self.reelRowSelect)],
            returning: ProfileReelRow.self
        )
        if let mapped = mapReel(row) {
            return mapped
        }
        if let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            let loaded = try await self.reel(id: ReelID(id))
            return loaded.reel
        }
        return reel
    }

    /// Public media URLs on this row. A missing row returns an empty list.
    private func mediaURLs(from table: String, id: String, columns: String) async throws -> [String?] {
        struct Row: Decodable, Sendable {
            var image_url: String?
            var video_url: String?
            var thumbnail_url: String?
        }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: table,
            query: [
                SupabaseQuery.select(columns),
                SupabaseQuery.eq("id", id),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = rows.first else { return [] }
        return [row.image_url, row.video_url, row.thumbnail_url]
    }

    func deleteReel(id: ReelID) async throws {
        let media = try? await mediaURLs(
            from: "reels",
            id: id.rawValue,
            columns: "video_url,thumbnail_url"
        )
        try await supabase.database.delete(
            from: "reels",
            query: [SupabaseQuery.eq("id", id.rawValue)]
        )
        await OwnedMediaStorageCleanup.removePublicObjects(
            urls: media ?? [],
            storage: supabase.storage
        )
    }

    func unattachedReels(
        for profileID: ProfileID,
        limit: Int,
        includingReelID: ReelID?
    ) async throws -> [Reel] {
        let bounded = min(max(limit, 1), 40)
        let rows: [ProfileReelRow] = try await supabase.database.select(
            ProfileReelRow.self,
            from: "reels",
            query: [
                SupabaseQuery.select(Self.reelRowSelect),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "trade_id", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: String(bounded)),
            ]
        )
        var reels = rows.compactMap(mapReel)
        if let includingReelID {
            let included = Set(reels.map(\.id))
            if !included.contains(includingReelID) {
                let preservedRows: [ProfileReelRow] = try await supabase.database.select(
                    ProfileReelRow.self,
                    from: "reels",
                    query: [
                        SupabaseQuery.select(Self.reelRowSelect),
                        SupabaseQuery.eq("user_id", profileID.rawValue),
                        SupabaseQuery.eq("id", includingReelID.rawValue),
                        URLQueryItem(name: "limit", value: "1"),
                    ]
                )
                if let preserved = preservedRows.compactMap(mapReel).first {
                    reels.insert(preserved, at: 0)
                }
            }
        }
        return Array(reels.prefix(bounded))
    }

    func tradeIDsWithAttachedReels(owner: ProfileID) async throws -> Set<TradeID> {
        struct Row: Decodable { var trade_id: String? }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "reels",
            query: [
                SupabaseQuery.select("trade_id"),
                SupabaseQuery.eq("user_id", owner.rawValue),
                URLQueryItem(name: "trade_id", value: "not.is.null"),
            ]
        )
        let ids = rows.compactMap { row -> TradeID? in
            guard let raw = row.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { return nil }
            return TradeID(raw)
        }
        return Set(ids)
    }

    func attachReel(id: ReelID, to tradeID: TradeID) async throws {
        guard let rawOwner = await session.currentUserID?.rawValue else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let ownerID = ProfileID(rawOwner)
        try await validateReelTradeLinkEligibility(
            reelID: id,
            tradeID: tradeID,
            ownerID: ownerID
        )
        let tradeIsPublic = try await tradeIsPublicFlag(tradeID: tradeID)
        try await linkReelToTrade(
            reelID: id,
            tradeID: tradeID,
            ownerID: ownerID,
            tradeIsPublic: tradeIsPublic,
            linkJobID: nil
        )
    }

    func linkReelToTrade(
        reelID: ReelID,
        tradeID: TradeID,
        ownerID: ProfileID,
        tradeIsPublic: Bool,
        linkJobID: String?
    ) async throws {
        try await validateReelTradeLinkEligibility(
            reelID: reelID,
            tradeID: tradeID,
            ownerID: ownerID
        )

        let query: [URLQueryItem] = [
            SupabaseQuery.eq("id", reelID.rawValue),
            SupabaseQuery.eq("user_id", ownerID.rawValue),
        ]
        let body = ReelTradeLinkPatchBody(
            tradeID: tradeID.rawValue,
            tradeIsPublic: tradeIsPublic
        )

        do {
            if let transport = supabase.transport {
                let response = try await transport.send(
                    host: .supabase,
                    path: "/rest/v1/reels",
                    method: .patch,
                    queryItems: query,
                    headers: [
                        "Prefer": "return=minimal",
                        "Accept": "application/json",
                    ],
                    body: try transport.encodeJSON(body)
                )
                TradeReelLinkDiagnostics.logResponse(
                    jobID: linkJobID,
                    tradeID: tradeID.rawValue,
                    reelID: reelID.rawValue,
                    httpStatus: response.statusCode,
                    responseData: response.data
                )
                if !response.isSuccessful {
                    throw SupabaseErrorMapping.mapNetwork(
                        NetworkErrorMapper().map(
                            data: response.data,
                            response: response.httpURLResponse,
                            error: nil
                        ) ?? NetworkError.unknown(message: "Reel link PATCH failed")
                    )
                }
            } else {
                try await supabase.database.update(body, table: "reels", query: query)
                TradeReelLinkDiagnostics.logResponse(
                    jobID: linkJobID,
                    tradeID: tradeID.rawValue,
                    reelID: reelID.rawValue,
                    httpStatus: 204,
                    responseData: Data()
                )
            }
        } catch {
            if case AppError.transport(.validation(let statusCode, let message)) = error {
                TradeReelLinkDiagnostics.logResponse(
                    jobID: linkJobID,
                    tradeID: tradeID.rawValue,
                    reelID: reelID.rawValue,
                    httpStatus: statusCode ?? 0,
                    responseData: message.data(using: .utf8) ?? Data()
                )
            }
            throw error
        }

        struct LinkedReelRow: Decodable {
            var id: String?
        }
        let linked: [LinkedReelRow] = try await supabase.database.select(
            LinkedReelRow.self,
            from: "reels",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("id", reelID.rawValue),
                SupabaseQuery.eq("user_id", ownerID.rawValue),
                SupabaseQuery.eq("trade_id", tradeID.rawValue),
            ]
        )
        guard linked.first?.id != nil else {
            throw AppError.domain(.notFound(entity: "reels", id: reelID.rawValue))
        }
    }

    private func tradeIsPublicFlag(tradeID: TradeID) async throws -> Bool {
        struct Row: Decodable { var is_public: Bool? }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "trades",
            query: [
                SupabaseQuery.select("is_public"),
                SupabaseQuery.eq("id", tradeID.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first?.is_public ?? false
    }

    private func validateReelTradeLinkEligibility(
        reelID: ReelID,
        tradeID: TradeID,
        ownerID: ProfileID
    ) async throws {
        struct ReelLinkRow: Decodable { var trade_id: String? }
        let reelRows: [ReelLinkRow] = try await supabase.database.select(
            ReelLinkRow.self,
            from: "reels",
            query: [
                SupabaseQuery.select("trade_id"),
                SupabaseQuery.eq("id", reelID.rawValue),
                SupabaseQuery.eq("user_id", ownerID.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard reelRows.first != nil else {
            throw AppError.domain(.notFound(entity: "reels", id: reelID.rawValue))
        }
        if let linked = reelRows.first?.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !linked.isEmpty
        {
            if linked == tradeID.rawValue {
                return
            }
            throw AppError.domain(.conflict(message: "This clip is already linked to another trade."))
        }
        if try await tradeHasAttachedReel(tradeID) {
            throw AppError.domain(.conflict(message: "This trade already has a clip attached."))
        }
    }

    func tradeHasAttachedReel(_ tradeID: TradeID) async throws -> Bool {
        guard let userID = await session.currentUserID else {
            return false
        }
        let ownerID = ProfileID(userID.rawValue)
        struct Row: Codable { var id: String? }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "reels",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("trade_id", tradeID.rawValue),
                SupabaseQuery.eq("user_id", ownerID.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return !rows.isEmpty
    }

    func tradePublicFlagForReelLink(tradeID: TradeID, ownerID: ProfileID) async throws -> Bool? {
        guard try await tradeOwnedByAuthor(tradeID: tradeID, authorID: ownerID) else {
            return nil
        }
        return try await tradeIsPublicFlag(tradeID: tradeID)
    }

    private func tradeOwnedByAuthor(tradeID: TradeID, authorID: ProfileID) async throws -> Bool {
        struct Row: Decodable { var id: String? }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "trades",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("id", tradeID.rawValue),
                SupabaseQuery.eq("user_id", authorID.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first?.id != nil
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
            let raw = row.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw?.isEmpty == false { return raw }
            if ReelCaptionLegacySupport.shouldFillCaptionFromLinkedTrade(
                tradeID: row.trade_id,
                createdAt: row.created_at,
                dbCaption: row.caption
            ) {
                return ReelCaptionLegacySupport.tradePublicCaption(
                    from: Self.resolveTradeJoin(row)?.public_description
                )
            }
            return nil
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

    private func mapEmbeddedTrade(from row: ProfileReelRow, viewerID: ProfileID? = nil) -> Trade? {
        let tradeIDRaw = row.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tradeIDRaw.isEmpty else { return nil }
        guard let join = Self.resolveTradeJoin(row) else { return nil }
        let isReelOwner = viewerID?.rawValue == row.user_id
        guard join.is_public != false || isReelOwner else { return nil }

        var dto = TradeDTO.Trade()
        dto.id = join.id ?? tradeIDRaw
        dto.user_id = row.user_id
        dto.ticker = join.ticker
        dto.direction = join.direction
        dto.public_description = join.public_description
        dto.pnl = join.pnl
        dto.rr = join.rr
        dto.is_public = join.is_public ?? true
        dto.created_at = row.created_at
        return try? TradeMapper.mapToDomain(dto)
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

        // PostgREST `in` filter, same as web hydrate.
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

