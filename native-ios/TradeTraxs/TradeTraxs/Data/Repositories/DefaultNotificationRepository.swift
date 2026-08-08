import Foundation

nonisolated struct DefaultNotificationRepository: NotificationRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

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
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        let items = rows.compactMap(mapNotification)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func unreadCount() async throws -> Int {
        guard let userID = await session.currentUserID else { return 0 }
        let rows: [NotificationDTO.Item] = try await supabase.database.select(
            NotificationDTO.Item.self,
            from: "notifications",
            query: [
                SupabaseQuery.select("id"),
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "read", value: "eq.false"),
                URLQueryItem(name: "limit", value: "1000"),
            ]
        )
        return rows.count
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
        _ = try await supabase.database.update(
            Body(read: true),
            table: "notifications",
            query: [
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "read", value: "eq.false"),
            ],
            returning: NotificationDTO.Item.self
        )
    }

    private func mapNotification(_ dto: NotificationDTO.Item) -> ActivityNotification? {
        guard let id = dto.id else { return nil }
        let kindRaw = dto.kind ?? dto.type ?? "system"
        let kind = ActivityNotificationKind(rawValue: kindRaw) ?? .system
        return ActivityNotification(
            id: NotificationID(id),
            kind: kind,
            actorProfileID: (dto.actor_profile_id ?? dto.sender_id).map { ProfileID($0) },
            title: dto.title ?? kindRaw,
            body: dto.body ?? dto.content ?? "",
            tradeID: dto.trade_id.map { TradeID($0) },
            postID: dto.post_id.map { PostID($0) },
            conversationID: nil,
            roomID: nil,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            isRead: dto.is_read ?? dto.read ?? false
        )
    }
}
