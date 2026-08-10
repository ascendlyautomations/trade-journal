import Foundation

nonisolated struct DefaultNotificationPreferencesRepository: NotificationPreferencesRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    private static let selectColumns = [
        "user_id",
        "notifications_enabled",
        "likes_enabled",
        "comments_enabled",
        "replies_enabled",
        "mentions_enabled",
        "reactions_enabled",
        "followers_enabled",
        "follow_requests_enabled",
        "follow_request_accepts_enabled",
        "direct_messages_enabled",
        "story_replies_enabled",
        "shares_enabled",
        "room_messages_enabled",
        "room_mentions_enabled",
        "room_joins_enabled",
        "achievement_likes_enabled",
        "achievement_comments_enabled",
        "achievement_unlocks_enabled",
        "product_updates_enabled",
        "maintenance_enabled",
        "announcements_enabled",
        "updated_at",
    ].joined(separator: ",")

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func preferences(for userID: ProfileID) async throws -> NotificationPreferences {
        let cacheKey = Self.cacheKey(userID)
        if let cached = cache.memory.value(forKey: cacheKey, as: NotificationPreferences.self) {
            return cached
        }

        let prefs: NotificationPreferences
        do {
            let rows: [NotificationPreferencesDTO] = try await supabase.database.select(
                NotificationPreferencesDTO.self,
                from: "notification_preferences",
                query: [
                    SupabaseQuery.select(Self.selectColumns),
                    SupabaseQuery.eq("user_id", userID.rawValue),
                    URLQueryItem(name: "limit", value: "1"),
                ]
            )
            if let dto = rows.first {
                prefs = Self.map(dto, fallbackUserID: userID)
            } else {
                prefs = .defaults(for: userID)
            }
        } catch {
            // Mirror web: on load failure, fall back to defaults rather than blocking Settings.
            prefs = .defaults(for: userID)
        }
        cache.memory.set(prefs, forKey: cacheKey)
        return prefs
    }

    func update(
        _ patch: [NotificationPreferenceKey: Bool],
        for userID: ProfileID
    ) async throws -> NotificationPreferences {
        guard !patch.isEmpty else {
            return try await preferences(for: userID)
        }

        var body: [String: Bool] = [:]
        for (key, value) in patch {
            body[key.rawValue] = value
        }

        let payload = NotificationPreferencesUpsertBody(
            user_id: userID.rawValue,
            patch: body,
            updated_at: ISO8601.string(from: Date())
        )

        let dto: NotificationPreferencesDTO = try await supabase.database.upsert(
            payload,
            into: "notification_preferences",
            onConflict: "user_id",
            returning: NotificationPreferencesDTO.self,
            select: Self.selectColumns
        )

        let prefs = Self.map(dto, fallbackUserID: userID)
        cache.memory.set(prefs, forKey: Self.cacheKey(userID))
        return prefs
    }

    private static func cacheKey(_ userID: ProfileID) -> String {
        "notification-preferences:\(userID.rawValue)"
    }

    private static func map(
        _ dto: NotificationPreferencesDTO,
        fallbackUserID: ProfileID
    ) -> NotificationPreferences {
        let userID = ProfileID(dto.user_id ?? fallbackUserID.rawValue)
        var values = NotificationPreferences.defaults(for: userID).values
        func apply(_ key: NotificationPreferenceKey, _ raw: Bool?) {
            if let raw { values[key] = raw }
        }
        apply(.notificationsEnabled, dto.notifications_enabled)
        apply(.likesEnabled, dto.likes_enabled)
        apply(.commentsEnabled, dto.comments_enabled)
        apply(.repliesEnabled, dto.replies_enabled)
        apply(.mentionsEnabled, dto.mentions_enabled)
        apply(.reactionsEnabled, dto.reactions_enabled)
        apply(.followersEnabled, dto.followers_enabled)
        apply(.followRequestsEnabled, dto.follow_requests_enabled)
        apply(.followRequestAcceptsEnabled, dto.follow_request_accepts_enabled)
        apply(.directMessagesEnabled, dto.direct_messages_enabled)
        apply(.storyRepliesEnabled, dto.story_replies_enabled)
        apply(.sharesEnabled, dto.shares_enabled)
        apply(.roomMessagesEnabled, dto.room_messages_enabled)
        apply(.roomMentionsEnabled, dto.room_mentions_enabled)
        apply(.roomJoinsEnabled, dto.room_joins_enabled)
        apply(.achievementLikesEnabled, dto.achievement_likes_enabled)
        apply(.achievementCommentsEnabled, dto.achievement_comments_enabled)
        apply(.achievementUnlocksEnabled, dto.achievement_unlocks_enabled)
        apply(.productUpdatesEnabled, dto.product_updates_enabled)
        apply(.maintenanceEnabled, dto.maintenance_enabled)
        apply(.announcementsEnabled, dto.announcements_enabled)
        return NotificationPreferences(
            userID: userID,
            values: values,
            updatedAt: dto.updated_at.flatMap(ISO8601.date(from:))
        )
    }
}

nonisolated struct NotificationPreferencesDTO: Codable, Sendable {
    var user_id: String?
    var notifications_enabled: Bool?
    var likes_enabled: Bool?
    var comments_enabled: Bool?
    var replies_enabled: Bool?
    var mentions_enabled: Bool?
    var reactions_enabled: Bool?
    var followers_enabled: Bool?
    var follow_requests_enabled: Bool?
    var follow_request_accepts_enabled: Bool?
    var direct_messages_enabled: Bool?
    var story_replies_enabled: Bool?
    var shares_enabled: Bool?
    var room_messages_enabled: Bool?
    var room_mentions_enabled: Bool?
    var room_joins_enabled: Bool?
    var achievement_likes_enabled: Bool?
    var achievement_comments_enabled: Bool?
    var achievement_unlocks_enabled: Bool?
    var product_updates_enabled: Bool?
    var maintenance_enabled: Bool?
    var announcements_enabled: Bool?
    var updated_at: String?
}

/// Encodes `user_id` + sparse boolean patch for PostgREST upsert.
nonisolated struct NotificationPreferencesUpsertBody: Encodable, Sendable {
    var user_id: String
    var patch: [String: Bool]
    var updated_at: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(user_id, forKey: DynamicCodingKey("user_id"))
        try container.encode(updated_at, forKey: DynamicCodingKey("updated_at"))
        for (key, value) in patch {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

nonisolated struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
