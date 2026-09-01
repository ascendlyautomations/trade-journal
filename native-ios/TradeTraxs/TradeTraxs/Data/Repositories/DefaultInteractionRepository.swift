import Foundation
import OSLog

/// Production likes/comments — mirrors web table routing (no invented RPCs).
nonisolated struct DefaultInteractionRepository: InteractionRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding

    init(supabase: SupabaseInfrastructure, session: any SessionProviding) {
        self.supabase = supabase
        self.session = session
    }

    func engagement(
        for targets: [InteractionTarget]
    ) async throws -> [InteractionTarget: EngagementSnapshot] {
        var result: [InteractionTarget: EngagementSnapshot] = [:]
        for target in targets {
            result[target] = .empty
        }
        guard !targets.isEmpty else { return result }

        let viewerID = await session.currentUserID?.rawValue
        var effectiveIDs: [InteractionTarget: String] = [:]
        effectiveIDs.reserveCapacity(targets.count)
        for target in targets {
            effectiveIDs[target] = try await effectiveContentID(for: target)
        }
        let grouped = Dictionary(grouping: targets, by: \.kind)

        // Parallelize per content-kind — same request count, lower wall-clock; each kind
        // still uses compact `fk` (+ user_id for likes) rather than full comment bodies.
        await withTaskGroup(of: (InteractionContentKind, [InteractionTarget: EngagementSnapshot]).self) {
            group in
            for (kind, groupTargets) in grouped {
                let ids = groupTargets.map { effectiveIDs[$0] ?? $0.id }
                guard !ids.isEmpty else { continue }
                group.addTask {
                    let snap = await Self.engagementForKind(
                        kind: kind,
                        targets: groupTargets,
                        ids: ids,
                        viewerID: viewerID,
                        database: self.supabase.database
                    )
                    return (kind, snap)
                }
            }
            for await (_, snap) in group {
                for (target, value) in snap {
                    result[target] = value
                }
            }
        }

        return result
    }

    private static func engagementForKind(
        kind: InteractionContentKind,
        targets: [InteractionTarget],
        ids: [String],
        viewerID: String?,
        database: any SupabaseDatabaseExecuting
    ) async -> [InteractionTarget: EngagementSnapshot] {
        let tables = tables(for: kind)
        let fk = tables.foreignKey

        async let likeRows: [InteractionDTO.LikeRow] = {
            (try? await database.select(
                InteractionDTO.LikeRow.self,
                from: tables.likes,
                query: [
                    SupabaseQuery.select("\(fk),user_id"),
                    SupabaseQuery.isIn(fk, ids),
                ]
            )) ?? []
        }()
        async let commentRows: [InteractionDTO.CommentCountRow] = {
            (try? await database.select(
                InteractionDTO.CommentCountRow.self,
                from: tables.comments,
                query: [
                    SupabaseQuery.select(fk),
                    SupabaseQuery.isIn(fk, ids),
                ]
            )) ?? []
        }()

        let likes = await likeRows
        let comments = await commentRows

        var likeCounts: [String: Int] = [:]
        var likedByMe: Set<String> = []
        for row in likes {
            guard let contentID = contentID(from: row, kind: kind) else { continue }
            likeCounts[contentID, default: 0] += 1
            if let viewerID, row.user_id == viewerID {
                likedByMe.insert(contentID)
            }
        }

        var commentCounts: [String: Int] = [:]
        for row in comments {
            guard let contentID = contentID(from: row, kind: kind) else { continue }
            commentCounts[contentID, default: 0] += 1
        }

        var map: [InteractionTarget: EngagementSnapshot] = [:]
        for target in targets {
            map[target] = EngagementSnapshot(
                likeCount: likeCounts[target.id] ?? 0,
                commentCount: commentCounts[target.id] ?? 0,
                viewerHasLiked: likedByMe.contains(target.id)
            )
        }
        return map
    }

    func setLiked(_ liked: Bool, on target: InteractionTarget) async throws {
        guard let userID = await session.currentUserID?.rawValue else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let contentID = try await effectiveContentID(for: target)
        let tables = Self.tables(for: target.kind)
        let fk = tables.foreignKey

        if liked {
            struct Body: Encodable, Decodable {
                var trade_id: String?
                var profile_post_id: String?
                var reel_id: String?
                var post_id: String?
                var achievement_post_id: String?
                var user_id: String
            }
            var body = Body(user_id: userID)
            switch target.kind {
            case .trade: body.trade_id = contentID
            case .profilePost: body.profile_post_id = contentID
            case .reel: body.reel_id = contentID
            case .feedPost: body.post_id = contentID
            case .achievement: body.achievement_post_id = contentID
            }
            do {
                _ = try await supabase.database.insert(
                    body,
                    into: tables.likes,
                    returning: Body.self
                )
            } catch {
                // Web treats unique-violation (23505) as success.
                if Self.isUniqueViolation(error) { return }
                throw error
            }
        } else {
            try await supabase.database.delete(
                from: tables.likes,
                query: [
                    SupabaseQuery.eq(fk, contentID),
                    SupabaseQuery.eq("user_id", userID),
                ]
            )
        }
    }

    func comments(
        for target: InteractionTarget,
        order: CommentSortOrder
    ) async throws -> [InteractionComment] {
        let contentID = try await effectiveContentID(for: target)
        let tables = Self.tables(for: target.kind)
        let fk = tables.foreignKey
        let ascending = order == .oldest
        let rows: [InteractionDTO.CommentRow] = try await supabase.database.select(
            InteractionDTO.CommentRow.self,
            from: tables.comments,
            query: [
                SupabaseQuery.select(Self.commentSelect(foreignKey: fk)),
                SupabaseQuery.eq(fk, contentID),
                URLQueryItem(
                    name: "order",
                    value: ascending ? "created_at.asc" : "created_at.desc"
                ),
            ]
        )
        return rows.compactMap { Self.mapComment($0, target: target) }
    }

    func addComment(
        body: String,
        parentID: CommentID?,
        on target: InteractionTarget
    ) async throws -> InteractionComment {
        guard let userID = await session.currentUserID?.rawValue else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.network(.validation(statusCode: nil, message: "Comment cannot be empty"))
        }

        let tables = Self.tables(for: target.kind)
        struct Body: Encodable {
            var trade_id: String?
            var profile_post_id: String?
            var reel_id: String?
            var post_id: String?
            var achievement_post_id: String?
            var user_id: String
            var content: String
            var parent_comment_id: String?
        }
        let contentID = try await effectiveContentID(for: target)
        var insert = Body(user_id: userID, content: trimmed, parent_comment_id: parentID?.rawValue)
        switch target.kind {
        case .trade: insert.trade_id = contentID
        case .profilePost: insert.profile_post_id = contentID
        case .reel: insert.reel_id = contentID
        case .feedPost: insert.post_id = contentID
        case .achievement: insert.achievement_post_id = contentID
        }

        // Same profiles embed as list load — no follow-up profile query after create.
        let row: InteractionDTO.CommentRow = try await supabase.database.insert(
            insert,
            into: tables.comments,
            query: [SupabaseQuery.select(Self.commentSelect(foreignKey: tables.foreignKey))],
            returning: InteractionDTO.CommentRow.self
        )
        guard let mapped = Self.mapComment(row, target: target) else {
            throw AppError.unknown(message: "Failed to map comment")
        }
        return mapped
    }

    func deleteComment(id: CommentID, on target: InteractionTarget) async throws {
        guard let userID = await session.currentUserID?.rawValue else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let tables = Self.tables(for: target.kind)
        try await supabase.database.delete(
            from: tables.comments,
            query: [
                SupabaseQuery.eq("id", id.rawValue),
                SupabaseQuery.eq("user_id", userID),
            ]
        )
    }

    func commentLikeMeta(
        for commentIDs: [CommentID],
        source: CommentLikeSource
    ) async throws -> [CommentID: CommentLikeSnapshot] {
        let unique = Array(Set(commentIDs)).filter { !$0.rawValue.isEmpty }
        guard !unique.isEmpty else { return [:] }

        let viewerID = await session.currentUserID?.rawValue
        let ids = unique.map(\.rawValue)
        let rows: [InteractionDTO.CommentLikeRow] = try await supabase.database.select(
            InteractionDTO.CommentLikeRow.self,
            from: "comment_likes",
            query: [
                SupabaseQuery.select("comment_id,user_id"),
                SupabaseQuery.eq("comment_source", source.rawValue),
                SupabaseQuery.isIn("comment_id", ids),
            ]
        )
        let tuples = rows.compactMap { row -> (commentID: String, userID: String)? in
            guard let commentID = row.comment_id, let userID = row.user_id else { return nil }
            return (commentID, userID)
        }
        return CommentLikeSemantics.aggregateMeta(
            rows: tuples,
            commentIDs: unique,
            viewerUserID: viewerID
        )
    }

    func setCommentLiked(
        _ liked: Bool,
        commentID: CommentID,
        source: CommentLikeSource
    ) async throws {
        guard let userID = await session.currentUserID?.rawValue else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let trimmed = commentID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if liked {
            struct Body: Encodable {
                var comment_source: String
                var comment_id: String
                var user_id: String
            }
            let body = Body(
                comment_source: source.rawValue,
                comment_id: trimmed,
                user_id: userID
            )
            do {
                _ = try await supabase.database.insert(
                    body,
                    into: "comment_likes",
                    returning: InteractionDTO.CommentLikeRow.self
                )
            } catch {
                if Self.isUniqueViolation(error) { return }
                throw error
            }
        } else {
            try await supabase.database.delete(
                from: "comment_likes",
                query: [
                    SupabaseQuery.eq("comment_source", source.rawValue),
                    SupabaseQuery.eq("comment_id", trimmed),
                    SupabaseQuery.eq("user_id", userID),
                ]
            )
        }
    }

    func setCommentPinned(
        _ pinned: Bool,
        commentID: CommentID,
        on target: InteractionTarget
    ) async throws {
        let trimmed = commentID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tables = Self.tables(for: target.kind)
        struct Body: Encodable { var pinned: Bool }
        try await supabase.database.update(
            Body(pinned: pinned),
            table: tables.comments,
            query: [SupabaseQuery.eq("id", trimmed)]
        )
    }

    // MARK: - Routing (web parity)

    private func effectiveContentID(for target: InteractionTarget) async throws -> String {
        switch target.kind {
        case .achievement:
            return try await AchievementInteractionPostIDResolver.shared.postID(
                for: target.id,
                database: supabase.database
            )
        default:
            return target.id
        }
    }

    private struct Tables {
        var likes: String
        var comments: String
        var foreignKey: String
    }

    private static func tables(for kind: InteractionContentKind) -> Tables {
        switch kind {
        case .trade:
            return Tables(likes: "trade_likes", comments: "trade_comments", foreignKey: "trade_id")
        case .profilePost:
            return Tables(
                likes: "profile_post_likes",
                comments: "profile_post_comments",
                foreignKey: "profile_post_id"
            )
        case .reel:
            return Tables(likes: "reel_likes", comments: "reel_comments", foreignKey: "reel_id")
        case .feedPost:
            return Tables(likes: "likes", comments: "comments", foreignKey: "post_id")
        case .achievement:
            return Tables(
                likes: "achievement_post_likes",
                comments: "achievement_post_comments",
                foreignKey: "achievement_post_id"
            )
        }
    }

    private static func contentID(from row: InteractionDTO.LikeRow, kind: InteractionContentKind) -> String? {
        switch kind {
        case .trade: return row.trade_id
        case .profilePost: return row.profile_post_id
        case .reel: return row.reel_id
        case .feedPost: return row.post_id
        case .achievement: return row.achievement_post_id
        }
    }

    private static func contentID(
        from row: InteractionDTO.CommentCountRow,
        kind: InteractionContentKind
    ) -> String? {
        switch kind {
        case .trade: return row.trade_id
        case .profilePost: return row.profile_post_id
        case .reel: return row.reel_id
        case .feedPost: return row.post_id
        case .achievement: return row.achievement_post_id
        }
    }

    private static func commentSelect(foreignKey: String) -> String {
        "id,\(foreignKey),user_id,content,parent_comment_id,pinned,created_at,profiles(username,name,avatar_url)"
    }

    /// Maps a comment row including the embedded author avatar URL from the list join.
    static func mapComment(
        _ row: InteractionDTO.CommentRow,
        target: InteractionTarget
    ) -> InteractionComment? {
        guard let id = row.id, let author = row.user_id else { return nil }
        let text = (row.content ?? row.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let avatar = row.profiles?.avatar_url?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = row.profiles?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return InteractionComment(
            id: CommentID(id),
            target: target,
            authorProfileID: ProfileID(author),
            authorUsername: row.profiles?.username,
            authorDisplayName: (displayName?.isEmpty == false) ? displayName : nil,
            authorAvatarURL: (avatar?.isEmpty == false) ? avatar : nil,
            body: text,
            parentCommentID: row.parent_comment_id.map { CommentID($0) },
            createdAt: ISO8601.date(from: row.created_at) ?? Date(),
            isPinned: row.pinned ?? false
        )
    }

    private static func isUniqueViolation(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("23505") || text.contains("duplicate") || text.contains("unique")
    }
}
