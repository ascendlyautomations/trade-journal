import Foundation

// DTOs exist ONLY in Data. Snake_case Codable shapes mirror Supabase transport, not Domain.

nonisolated enum TradeDTO {
    struct Trade: Codable, Sendable {
        var id: String?
        var user_id: String?
        var account_id: String?
        var ticker: String?
        var direction: String?
        var mode: String?
        var contracts: FlexibleNumber?
        var entry_price: FlexibleNumber?
        var exit_price: FlexibleNumber?
        var entry_time: String?
        var exit_time: String?
        var pnl: FlexibleNumber?
        var rr: FlexibleNumber?
        var points: FlexibleNumber?
        var session: String?
        var is_public: Bool?
        var public_description: String?
        var image_url: String?
        var notes: String?
        var created_at: String?
        var date: String?
    }

    struct Image: Codable, Sendable {
        var id: String?
        var trade_id: String?
        var storage_path: String?
        var sort_order: Int?
    }

    struct Note: Codable, Sendable {
        var id: String?
        var trade_id: String?
        var body: String?
        var created_at: String?
        var updated_at: String?
    }

    struct Account: Codable, Sendable {
        var id: String?
        var user_id: String?
        var name: String?
        var category: String?
        var mode: String?
        var size: FlexibleNumber?
        var is_active: Bool?
        var can_add_trades: Bool?
    }

    struct InsertBody: Encodable, Sendable {
        var user_id: String
        var account_id: String?
        var ticker: String
        var direction: String
        var mode: String?
        var contracts: Double
        var entry_price: Double?
        var exit_price: Double?
        var entry_time: String?
        var exit_time: String?
        var pnl: Double?
        var rr: Double?
        var is_public: Bool
        var public_description: String?
        var created_at: String
        var date: String
    }
}

nonisolated enum ProfileDTO {
    struct User: Codable, Sendable {
        var id: String?
        var email: String?
        var created_at: String?
    }

    struct Profile: Codable, Sendable {
        var id: String?
        var username: String?
        var name: String?
        var bio: String?
        var avatar_url: String?
        var trader_type: String?
        var is_private: Bool?
        var is_creator: Bool?
        var is_pro: Bool?
        var subscription_status: String?
        var created_at: String?
        var referral_code: String?
    }

    struct UpdateBody: Encodable, Sendable {
        var username: String?
        var name: String?
        var bio: String?
        var avatar_url: String?
        var trader_type: String?
        var is_private: Bool?
    }
}

nonisolated enum FeedDTO {
    struct Item: Codable, Sendable {
        var id: String?
        var kind: String?
        var author_profile_id: String?
        var user_id: String?
        var created_at: String?
        var trade_id: String?
        var post_id: String?
        var reel_id: String?
        var caption: String?
        var content: String?
        var like_count: Int?
        var comment_count: Int?
        var viewer_has_liked: Bool?
    }

    struct Post: Codable, Sendable {
        var id: String?
        var user_id: String?
        var body: String?
        var content: String?
        var visibility: String?
        var trade_id: String?
        var created_at: String?
        var updated_at: String?
    }

    struct Comment: Codable, Sendable {
        var id: String?
        var post_id: String?
        var user_id: String?
        var body: String?
        var content: String?
        var parent_comment_id: String?
        var created_at: String?
    }
}

nonisolated enum MessageDTO {
    struct Conversation: Codable, Sendable {
        var id: String?
        var participant_ids: [String]?
        var last_message_preview: String?
        var last_message_at: String?
        var unread_count: Int?
        var updated_at: String?
        var created_at: String?
    }

    struct Message: Codable, Sendable {
        var id: String?
        var conversation_id: String?
        var sender_id: String?
        var sender_profile_id: String?
        var kind: String?
        var body: String?
        var content: String?
        var created_at: String?
        var is_read: Bool?
    }
}

nonisolated enum RoomDTO {
    struct Room: Codable, Sendable {
        var id: String?
        var owner_id: String?
        var owner_profile_id: String?
        var name: String?
        var slug: String?
        var description: String?
        var member_count: Int?
        var show_on_profile: Bool?
        var image_url: String?
        var created_at: String?
    }

    struct Message: Codable, Sendable {
        var id: String?
        var room_id: String?
        var sender_id: String?
        var sender_profile_id: String?
        var body: String?
        var content: String?
        var created_at: String?
        var is_pinned: Bool?
    }

    struct Membership: Codable, Sendable {
        var room_id: String?
        var user_id: String?
        var role: String?
        var joined_at: String?
    }
}

nonisolated enum NotificationDTO {
    struct Item: Codable, Sendable {
        var id: String?
        var type: String?
        var kind: String?
        var user_id: String?
        var sender_id: String?
        var actor_profile_id: String?
        var title: String?
        var content: String?
        var body: String?
        var created_at: String?
        var read: Bool?
        var is_read: Bool?
        var trade_id: String?
        var post_id: String?
    }
}

nonisolated enum CalendarDTO {
    struct Event: Codable, Sendable {
        var id: String?
        var owner_profile_id: String?
        var user_id: String?
        var kind: String?
        var title: String?
        var day: String?
        var trade_ids: [String]?
        var note: String?
    }
}

nonisolated enum BillingDTO {
    struct Status: Codable, Sendable {
        var id: String?
        var profile_id: String?
        var plan: String?
        var lifecycle: String?
        var is_pro: Bool?
        var subscription_status: String?
    }

    struct Subscription: Codable, Sendable {
        var id: String?
        var profile_id: String?
        var plan: String?
        var interval: String?
        var lifecycle: String?
        var trial_ends_at: String?
        var renews_at: String?
    }
}

nonisolated enum ReferralDTO {
    struct Referral: Codable, Sendable {
        var id: String?
        var referrer_profile_id: String?
        var referrer_id: String?
        var code: String?
        var referral_code: String?
        var invitee_profile_id: String?
        var created_at: String?
        var completed_at: String?
    }
}

nonisolated enum AnalyticsDTO {
    struct Event: Codable, Sendable {
        var name: String?
        var properties: [String: String]?
        var occurred_at: String?
    }
}

nonisolated enum AchievementDTO {
    struct Achievement: Codable, Sendable {
        var id: String?
        var owner_profile_id: String?
        var user_id: String?
        var kind: String?
        var title: String?
        var tier: String?
        var is_public: Bool?
        var achieved_at: String?
    }
}

nonisolated enum LeaderboardDTO {
    struct Entry: Codable, Sendable {
        var rank: Int?
        var profile_id: String?
        var user_id: String?
        var username: String?
        var total_pnl: FlexibleNumber?
        var pnl: FlexibleNumber?
        var trade_count: Int?
    }

    struct TradeRow: Codable, Sendable {
        var user_id: String?
        var pnl: FlexibleNumber?
        var rr: FlexibleNumber?
        var created_at: String?
        var account_type: String?
        var mode: String?
    }
}

nonisolated enum SearchDTO {
    struct Result: Codable, Sendable {
        var id: String?
        var kind: String?
        var title: String?
        var subtitle: String?
        var profile_id: String?
        var trade_id: String?
        var username: String?
        var name: String?
    }
}

nonisolated enum HomeDTO {
    struct Dashboard: Codable, Sendable {
        var refreshed_at: String?
        var current_streak_days: Int?
        var total_pnl: FlexibleNumber?
        var trade_count: Int?
        var win_count: Int?
        var loss_count: Int?
    }

    struct StreakBundle: Codable, Sendable {
        var onboarding_completed: Bool?
        var trade_count: Int?
        var public_trade_count: Int?
        var profile_post_count: Int?
        var reel_count: Int?
        var comment_count: Int?
        var likes_received_count: Int?
    }
}
