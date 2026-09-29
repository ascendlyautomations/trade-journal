import Foundation

nonisolated enum AdminContentReportHydration {
    static func enrich(
        database: any SupabaseDatabaseExecuting,
        rows: [AdminContentReportRow]
    ) async throws -> AdminContentReportEnrichment {
        var profiles = try await fetchProfiles(database: database, ids: collectUserIDs(rows))
        let targets = try await batchTargetPreviews(database: database, rows: rows, profiles: &profiles)
        return AdminContentReportEnrichment(profiles: profiles, targets: targets)
    }

    static func snapshot(
        row: AdminContentReportRow,
        enrichment: AdminContentReportEnrichment
    ) -> AdminContentReportSnapshot {
        let key = targetKey(row.targetType, row.targetID)
        let preview = enrichment.targets[key] ?? missingPreview(row: row)
        let reportedID = resolveReportedUserID(row)
        return AdminContentReportSnapshot(
            row: row,
            targetPreview: preview,
            reporter: enrichment.profiles[row.reporterUserID],
            reportedUser: reportedID.flatMap { enrichment.profiles[$0] }
        )
    }

    static func listReportedSubjectLabel(
        row: AdminContentReportRow,
        enrichment: AdminContentReportEnrichment
    ) -> String {
        if row.targetType == .user {
            return ContentReportDisplay.profileHandle(enrichment.profiles[ProfileID(row.targetID)])
        }
        let preview = enrichment.targets[targetKey(row.targetType, row.targetID)] ?? missingPreview(row: row)
        let owner = preview.ownerUserID.flatMap { enrichment.profiles[$0] }
        if let handle = owner.map({ ContentReportDisplay.profileHandle($0) }) {
            return "\(ContentReportDisplay.targetLabel(row.targetType)) · \(handle)"
        }
        return preview.headline
    }

    static func resolveReportedUserID(_ row: AdminContentReportRow) -> ProfileID? {
        if let reported = row.reportedUserID { return reported }
        if row.targetType == .user { return ProfileID(row.targetID) }
        return nil
    }

    private static func targetKey(_ type: ContentReportTargetType, _ id: String) -> String {
        "\(type.rawValue):\(id)"
    }

    private static func collectUserIDs(_ rows: [AdminContentReportRow]) -> [ProfileID] {
        var ids = Set<ProfileID>()
        for row in rows {
            ids.insert(row.reporterUserID)
            if let reported = row.reportedUserID { ids.insert(reported) }
            if row.targetType == .user { ids.insert(ProfileID(row.targetID)) }
            if let reported = resolveReportedUserID(row) { ids.insert(reported) }
        }
        return Array(ids)
    }

    private static func fetchProfiles(
        database: any SupabaseDatabaseExecuting,
        ids: [ProfileID]
    ) async throws -> [ProfileID: AdminReportProfileSummary] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let query = [
            URLQueryItem(name: "select", value: "id,username,name,avatar_url,is_banned,banned_reason,banned_at"),
            URLQueryItem(name: "id", value: "in.(\(unique.map(\.rawValue).joined(separator: ",")))"),
        ]
        struct Row: Decodable {
            var id: String
            var username: String?
            var name: String?
            var avatar_url: String?
            var is_banned: Bool?
            var banned_reason: String?
            var banned_at: String?
        }
        let rows: [Row] = try await database.select(Row.self, from: "profiles", query: query)
        var map: [ProfileID: AdminReportProfileSummary] = [:]
        for row in rows {
            let id = ProfileID(row.id)
            map[id] = AdminReportProfileSummary(
                id: id,
                username: row.username,
                name: row.name,
                avatarURL: row.avatar_url,
                isBanned: row.is_banned ?? false,
                bannedReason: row.banned_reason,
                bannedAt: row.banned_at.flatMap { AdminContentReportParsing.date(from: $0) }
            )
        }
        return map
    }

    private static func batchTargetPreviews(
        database: any SupabaseDatabaseExecuting,
        rows: [AdminContentReportRow],
        profiles: inout [ProfileID: AdminReportProfileSummary]
    ) async throws -> [String: AdminReportTargetPreview] {
        var previews: [String: AdminReportTargetPreview] = [:]
        var idsByType: [ContentReportTargetType: [String]] = [:]
        for row in rows {
            idsByType[row.targetType, default: []].append(row.targetID)
        }
        for type in idsByType.keys {
            idsByType[type] = Array(Set(idsByType[type] ?? []))
        }

        try await loadTrades(database: database, ids: idsByType[.trade] ?? [], profiles: profiles, into: &previews)
        try await loadPosts(database: database, ids: idsByType[.post] ?? [], profiles: profiles, into: &previews)
        try await loadReels(database: database, ids: idsByType[.reel] ?? [], profiles: profiles, into: &previews)
        try await loadAchievements(database: database, ids: idsByType[.achievement] ?? [], profiles: profiles, into: &previews)
        try await loadStories(database: database, ids: idsByType[.story] ?? [], profiles: profiles, into: &previews)
        try await loadComments(database: database, ids: idsByType[.comment] ?? [], profiles: profiles, into: &previews)
        try await loadDirectMessages(database: database, ids: idsByType[.directMessage] ?? [], profiles: profiles, into: &previews)
        try await loadRooms(database: database, ids: idsByType[.tradeRoom] ?? [], profiles: profiles, into: &previews)
        try await loadRoomMessages(database: database, ids: idsByType[.tradeRoomMessage] ?? [], profiles: profiles, into: &previews)

        for userID in idsByType[.user] ?? [] {
            let pid = ProfileID(userID)
            if profiles[pid] == nil {
                let extra = try await fetchProfiles(database: database, ids: [pid])
                profiles.merge(extra) { _, new in new }
            }
            previews[targetKey(.user, userID)] = userPreview(userID: pid, profiles: profiles)
        }

        for row in rows {
            let key = targetKey(row.targetType, row.targetID)
            if previews[key] == nil {
                previews[key] = row.targetType == .user
                    ? userPreview(userID: ProfileID(row.targetID), profiles: profiles)
                    : missingPreview(row: row)
            }
        }
        return previews
    }

    private static func userPreview(
        userID: ProfileID,
        profiles: [ProfileID: AdminReportProfileSummary]
    ) -> AdminReportTargetPreview {
        AdminReportTargetPreview(
            targetType: .user,
            targetID: userID.rawValue,
            headline: ContentReportDisplay.profileDisplayName(profiles[userID]),
            subline: ContentReportDisplay.profileHandle(profiles[userID]),
            ownerUserID: userID,
            unavailable: profiles[userID] == nil,
            openDestination: .profile(userID)
        )
    }

    private static func missingPreview(row: AdminContentReportRow) -> AdminReportTargetPreview {
        AdminReportTargetPreview(
            targetType: row.targetType,
            targetID: row.targetID,
            headline: "Deleted content",
            subline: "\(ContentReportDisplay.targetLabel(row.targetType)) may have been removed.",
            ownerUserID: resolveReportedUserID(row),
            unavailable: true,
            openDestination: nil
        )
    }

    private static func ownerHandle(
        _ ownerID: ProfileID?,
        profiles: [ProfileID: AdminReportProfileSummary]
    ) -> String? {
        guard let ownerID else { return nil }
        return ContentReportDisplay.profileHandle(profiles[ownerID])
    }

    private static func loadTrades(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var ticker: String?; var pnl: Double?; var user_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "trades",
            query: [
                URLQueryItem(name: "select", value: "id,ticker,pnl,user_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for trade in rows {
            let owner = trade.user_id.map { ProfileID($0) }
            let pnl = AdminContentReportParsing.formatPnL(trade.pnl)
            let ticker = (trade.ticker ?? "—").uppercased()
            previews[targetKey(.trade, trade.id)] = AdminReportTargetPreview(
                targetType: .trade,
                targetID: trade.id,
                headline: "\(pnl) | \(ticker)",
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Trade · \($0)" } ?? "Trade",
                ownerUserID: owner,
                unavailable: false,
                openDestination: .trade(TradeID(trade.id))
            )
        }
    }

    private static func loadPosts(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var caption: String?; var user_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "posts",
            query: [
                URLQueryItem(name: "select", value: "id,caption,user_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for post in rows {
            let owner = post.user_id.map { ProfileID($0) }
            let caption = (post.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            previews[targetKey(.post, post.id)] = AdminReportTargetPreview(
                targetType: .post,
                targetID: post.id,
                headline: caption.isEmpty ? "Post" : String(caption.prefix(80)),
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Post · \($0)" } ?? "Post",
                ownerUserID: owner,
                unavailable: false,
                openDestination: .post(PostID(post.id))
            )
        }
    }

    private static func loadReels(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var caption: String?; var user_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "reels",
            query: [
                URLQueryItem(name: "select", value: "id,caption,user_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for reel in rows {
            let owner = reel.user_id.map { ProfileID($0) }
            let caption = (reel.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            previews[targetKey(.reel, reel.id)] = AdminReportTargetPreview(
                targetType: .reel,
                targetID: reel.id,
                headline: caption.isEmpty ? "Reel" : String(caption.prefix(80)),
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Reel · \($0)" } ?? "Reel",
                ownerUserID: owner,
                unavailable: false,
                openDestination: .reel(ReelID(reel.id))
            )
        }
    }

    private static func loadAchievements(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var title: String?; var user_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "achievements",
            query: [
                URLQueryItem(name: "select", value: "id,title,user_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for item in rows {
            let owner = item.user_id.map { ProfileID($0) }
            let title = (item.title ?? "Achievement").trimmingCharacters(in: .whitespacesAndNewlines)
            previews[targetKey(.achievement, item.id)] = AdminReportTargetPreview(
                targetType: .achievement,
                targetID: item.id,
                headline: title,
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Achievement · \($0)" } ?? "Achievement",
                ownerUserID: owner,
                unavailable: false,
                openDestination: .achievement(AchievementID(item.id))
            )
        }
    }

    private static func loadStories(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var user_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "stories",
            query: [
                URLQueryItem(name: "select", value: "id,user_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for story in rows {
            let owner = story.user_id.map { ProfileID($0) }
            previews[targetKey(.story, story.id)] = AdminReportTargetPreview(
                targetType: .story,
                targetID: story.id,
                headline: "Story",
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Story · \($0)" } ?? "Story",
                ownerUserID: owner,
                unavailable: false,
                openDestination: nil
            )
        }
    }

    private static func loadComments(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var content: String?; var user_id: String?; var post_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "comments",
            query: [
                URLQueryItem(name: "select", value: "id,content,user_id,post_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for comment in rows {
            let owner = comment.user_id.map { ProfileID($0) }
            let content = (comment.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let openPost = comment.post_id.map { PostID($0) }.map { AdminReportOpenDestination.post($0) }
            previews[targetKey(.comment, comment.id)] = AdminReportTargetPreview(
                targetType: .comment,
                targetID: comment.id,
                headline: content.isEmpty ? "Comment" : String(content.prefix(80)),
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Comment · \($0)" } ?? "Comment",
                ownerUserID: owner,
                unavailable: false,
                openDestination: openPost
            )
        }
    }

    private static func loadDirectMessages(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var content: String?; var sender_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "direct_messages",
            query: [
                URLQueryItem(name: "select", value: "id,content,sender_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for message in rows {
            let owner = message.sender_id.map { ProfileID($0) }
            let content = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            previews[targetKey(.directMessage, message.id)] = AdminReportTargetPreview(
                targetType: .directMessage,
                targetID: message.id,
                headline: content.isEmpty ? "Direct message" : String(content.prefix(80)),
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Direct message · \($0)" } ?? "Direct message",
                ownerUserID: owner,
                unavailable: false,
                openDestination: nil
            )
        }
    }

    private static func loadRooms(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var name: String?; var owner_user_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "rooms",
            query: [
                URLQueryItem(name: "select", value: "id,name,owner_user_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for room in rows {
            let owner = room.owner_user_id.map { ProfileID($0) }
            let name = (room.name ?? "Trade Room").trimmingCharacters(in: .whitespacesAndNewlines)
            previews[targetKey(.tradeRoom, room.id)] = AdminReportTargetPreview(
                targetType: .tradeRoom,
                targetID: room.id,
                headline: name,
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Trade Room · \($0)" } ?? "Trade Room",
                ownerUserID: owner,
                unavailable: false,
                openDestination: .room(RoomID(room.id))
            )
        }
    }

    private static func loadRoomMessages(
        database: any SupabaseDatabaseExecuting,
        ids: [String],
        profiles: [ProfileID: AdminReportProfileSummary],
        into previews: inout [String: AdminReportTargetPreview]
    ) async throws {
        guard !ids.isEmpty else { return }
        struct Row: Decodable { var id: String; var content: String?; var user_id: String?; var room_id: String? }
        let rows: [Row] = try await database.select(
            Row.self,
            from: "room_messages",
            query: [
                URLQueryItem(name: "select", value: "id,content,user_id,room_id"),
                URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
            ]
        )
        for message in rows {
            let owner = message.user_id.map { ProfileID($0) }
            let content = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let openRoom = message.room_id.map { RoomID($0) }.map { AdminReportOpenDestination.room($0) }
            previews[targetKey(.tradeRoomMessage, message.id)] = AdminReportTargetPreview(
                targetType: .tradeRoomMessage,
                targetID: message.id,
                headline: content.isEmpty ? "Trade Room message" : String(content.prefix(80)),
                subline: owner.flatMap { ownerHandle($0, profiles: profiles) }.map { "Trade Room message · \($0)" } ?? "Trade Room message",
                ownerUserID: owner,
                unavailable: false,
                openDestination: openRoom
            )
        }
    }
}

nonisolated enum AdminContentReportParsing {
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func formatPnL(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatted = String(format: "%+.2f", value)
        return formatted
    }

    static func parseRow(_ dto: ContentReportRowDTO) -> AdminContentReportRow? {
        guard let targetType = ContentReportTargetType(rawValue: dto.target_type),
              let reason = ContentReportReason(rawValue: dto.reason),
              let status = ContentReportStatus(rawValue: dto.status)
        else { return nil }
        return AdminContentReportRow(
            id: dto.id,
            reporterUserID: ProfileID(dto.reporter_user_id),
            targetType: targetType,
            targetID: dto.target_id,
            reportedUserID: dto.reported_user_id.map { ProfileID($0) },
            reason: reason,
            details: dto.details,
            status: status,
            createdAt: dto.created_at.flatMap { date(from: $0) },
            reviewedAt: dto.reviewed_at.flatMap { date(from: $0) },
            reviewedBy: dto.reviewed_by.map { ProfileID($0) }
        )
    }
}

nonisolated struct ContentReportRowDTO: Decodable, Sendable {
    var id: String
    var reporter_user_id: String
    var target_type: String
    var target_id: String
    var reported_user_id: String?
    var reason: String
    var details: String?
    var status: String
    var created_at: String?
    var reviewed_at: String?
    var reviewed_by: String?
}
