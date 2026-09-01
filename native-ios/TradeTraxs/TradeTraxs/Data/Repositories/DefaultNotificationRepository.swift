import Foundation

nonisolated struct DefaultNotificationRepository: NotificationRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

    private static let profileSelect =
        "id,username,name,bio,avatar_url,trading_style,trader_type,primary_market,started_trading,is_private,created_at"

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.session = session
    }

    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification> {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let rows: [NotificationDTO.Item] = try await supabase.database.select(
            NotificationDTO.Item.self,
            from: "notifications",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select(NotificationDTO.selectColumns),
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.isIn("type", NotificationInboxType.all),
            ]
        )
        let items = rows.compactMap(Self.mapNotification)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func notification(id: NotificationID) async throws -> ActivityNotification? {
        let rows: [NotificationDTO.Item] = try await supabase.database.select(
            NotificationDTO.Item.self,
            from: "notifications",
            query: [
                SupabaseQuery.select(NotificationDTO.selectColumns),
                SupabaseQuery.eq("id", id.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first.flatMap(Self.mapNotification)
    }

    func unreadCount() async throws -> Int {
        guard let userID = await session.currentUserID else { return 0 }
        // PostgREST Prefer: count=exact — no notification row payloads transferred.
        return try await supabase.database.count(
            from: "notifications",
            query: [
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "read", value: "eq.false"),
                SupabaseQuery.isIn("type", NotificationInboxType.all),
            ]
        )
    }

    func markRead(id: NotificationID) async throws {
        struct Body: Encodable { var read: Bool }
        _ = try await supabase.database.update(
            Body(read: true),
            table: "notifications",
            query: [SupabaseQuery.eq("id", id.rawValue)],
            returning: NotificationDTO.Item.self
        )
    }

    func markAllRead() async throws {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        struct Body: Encodable { var read: Bool }
        // Bulk update — must not use single-row `Accept: application/vnd.pgrst.object+json`.
        try await supabase.database.update(
            Body(read: true),
            table: "notifications",
            query: [
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "read", value: "eq.false"),
                SupabaseQuery.isIn("type", NotificationInboxType.all),
            ]
        )
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        let unique = Array(Set(ids.map(\.rawValue))).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [] }
        let rows: [ProfileDTO.Profile] = try await supabase.database.select(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select(Self.profileSelect),
                SupabaseQuery.isIn("id", unique),
            ]
        )
        return rows.compactMap { try? ProfileMapper.mapToDomain($0) }
    }

    // MARK: - Mapping

    static func mapNotification(_ dto: NotificationDTO.Item) -> ActivityNotification? {
        guard let id = dto.id else { return nil }
        let kindRaw = dto.type ?? dto.kind ?? "system"
        let kind = ActivityNotificationKind.parse(kindRaw)
        guard kind.isInboxType || kind == .system || kind == .message else { return nil }

        let content = dto.content ?? dto.body ?? ""
        let parsed = ContentPayload.parse(content)

        let title: String
        if let parsedTitle = parsed.title, !parsedTitle.isEmpty {
            title = parsedTitle
        } else {
            title = kind.rawValue
        }

        let body: String
        if kind == .comment {
            body = content
        } else if let parsedBody = parsed.body, !parsedBody.isEmpty {
            body = parsedBody
        } else if kind != .comment {
            body = ""
        } else {
            body = content
        }

        let roomID = (dto.room_id ?? parsed.roomID).map { RoomID($0) }
        let resolvedReportID: ReportID? = {
            if let period = parsed.periodKey, !period.isEmpty {
                return ReportID(period)
            }
            if let href = parsed.href {
                return reportIdentifier(fromHref: href)
            }
            return nil
        }()

        return ActivityNotification(
            id: NotificationID(id),
            kind: kind,
            actorProfileID: (dto.actor_profile_id ?? dto.sender_id).map { ProfileID($0) },
            title: title,
            body: body,
            tradeID: dto.trade_id.map { TradeID($0) },
            postID: dto.post_id.map { PostID($0) },
            profilePostID: dto.profile_post_id.map { PostID($0) },
            achievementPostID: dto.achievement_post_id.map { PostID($0) },
            reelID: dto.reel_id.map { ReelID($0) },
            commentID: dto.comment_id.map { CommentID($0) },
            conversationID: nil,
            roomID: roomID,
            roomMessageID: (dto.room_message_id ?? parsed.messageID).map { RoomMessageID($0) },
            followRequestID: parsed.followRequestID,
            roomSlug: parsed.roomSlug,
            roomName: parsed.roomName,
            sectionID: parsed.sectionID,
            sectionName: parsed.sectionName,
            messagePreview: parsed.messagePreview,
            reportID: resolvedReportID,
            affiliateHref: parsed.href,
            isReply: parsed.isReply,
            isMention: parsed.isMention || kind == .roomMention,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            isRead: dto.is_read ?? dto.read ?? false
        )
    }

    private static func reportIdentifier(fromHref href: String) -> ReportID? {
        guard let components = URLComponents(string: href),
              let report = components.queryItems?.first(where: { $0.name == "report" })?.value,
              !report.isEmpty
        else { return nil }
        return ReportID(report)
    }

    private struct ContentPayload {
        var title: String?
        var body: String?
        var href: String?
        var followRequestID: String?
        var roomID: String?
        var roomSlug: String?
        var roomName: String?
        var sectionID: String?
        var sectionName: String?
        var messageID: String?
        var messagePreview: String?
        var periodKey: String?
        var isReply: Bool = false
        var isMention: Bool = false

        static func parse(_ content: String) -> ContentPayload {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ContentPayload()
            }

            func string(_ key: String) -> String? {
                guard let value = object[key] else { return nil }
                if let s = value as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
                return nil
            }

            func bool(_ key: String) -> Bool {
                guard let value = object[key] else { return false }
                if let flag = value as? Bool { return flag }
                if let number = value as? NSNumber { return number.boolValue }
                if let text = value as? String {
                    return text.lowercased() == "true" || text == "1"
                }
                return false
            }

            let commentKind = (string("comment_kind") ?? string("commentKind") ?? "").lowercased()
            let isReply = bool("is_reply") || commentKind == "reply" || string("parent_comment_id") != nil
            let isMention = bool("is_mention") || commentKind == "mention"

            return ContentPayload(
                title: string("title"),
                body: string("body"),
                href: string("href"),
                followRequestID: string("follow_request_id"),
                roomID: string("room_id"),
                roomSlug: string("room_slug"),
                roomName: string("room_name"),
                sectionID: string("section_id"),
                sectionName: string("section_name"),
                messageID: string("message_id"),
                messagePreview: string("message_preview"),
                periodKey: string("periodKey") ?? string("period_key") ?? string("periodId"),
                isReply: isReply,
                isMention: isMention
            )
        }
    }
}
