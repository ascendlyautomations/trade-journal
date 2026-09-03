import Foundation

// DTOs exist ONLY in Data. Snake_case Codable shapes mirror Supabase transport, not Domain.

nonisolated enum TradeDTO {
    /// Mirrors web `PUBLIC_TRADE_SELECT` / owner list fields used by Profile + Trade Detail.
    static let profileListSelect =
        "id,user_id,account_id,created_at,date,trade_date,pnl,rr,points,contracts,session,ticker,direction,notes,public_description,is_public,is_pinned,image_url,entry_time,exit_time,entry_price,exit_price,account_type,mode,strategy,duration_seconds,duration_text,trade_mode"

    /// Owner Trade Detail / Add Trade edit — includes psychology + journal review columns.
    static let ownerJournalSelect =
        profileListSelect
        + ",confidence,emotion,followed_plan,market_condition,timeframe,news_event,psychology_notes,exit_emotion,execution_rating,image_display_mode,reviewed,is_initial_import,import_source,import_fingerprint"

    /// Owner Trade History — includes denormalized account_name for search.
    static let historyListSelect =
        "id,user_id,account_id,account_name,created_at,date,trade_date,pnl,rr,points,contracts,session,ticker,direction,notes,public_description,is_public,is_pinned,image_url,entry_time,exit_time,entry_price,exit_price,account_type,mode,strategy,confidence,emotion,followed_plan,market_condition,timeframe,news_event,psychology_notes,exit_emotion,execution_rating,duration_seconds,duration_text,trade_mode,image_display_mode,reviewed,is_initial_import,import_source,import_fingerprint"

    /// Mirrors web `PROFILE_SUMMARY_TRADE_SELECT`.
    static let profileSummarySelect = "id,created_at,pnl,rr,mode,account_type"

    struct Trade: Codable, Sendable {
        var id: String?
        var user_id: String?
        var account_id: String?
        var ticker: String?
        var direction: String?
        var mode: String?
        var account_type: String?
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
        var is_pinned: Bool?
        var public_description: String?
        var image_url: String?
        var notes: String?
        var created_at: String?
        var date: String?
        var trade_date: String?
        var account_name: String?
        var strategy: String?
        var duration_seconds: FlexibleNumber?
        var duration_text: String?
        var trade_mode: String?
        var confidence: FlexibleNumber?
        var emotion: String?
        var followed_plan: Bool?
        var market_condition: String?
        var timeframe: String?
        var news_event: Bool?
        var psychology_notes: String?
        var exit_emotion: String?
        var execution_rating: FlexibleNumber?
        var image_display_mode: String?
        var reviewed: Bool?
        var is_initial_import: Bool?
        var import_source: String?
        var import_fingerprint: String?
    }

    /// Lightweight overview row — web `fetchSummaryTrades`.
    struct SummaryTrade: Codable, Sendable {
        var id: String?
        var created_at: String?
        var pnl: FlexibleNumber?
        var rr: FlexibleNumber?
        var mode: String?
        var account_type: String?
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
        /// Production column on `accounts` (web `ACCOUNTS_SELECT`).
        var name: String?
        /// Legacy / `user_accounts` registry column — not used for trade account resolution.
        var account_name: String?
        var account_type: String?
        var category: String?
        var mode: String?
        /// Web `accounts.account_size`.
        var account_size: FlexibleNumber?
        /// Legacy alias — prefer `account_size`.
        var size: FlexibleNumber?
        var account_number: String?
        var note: String?
        var is_active: Bool?
        var can_add_trades: Bool?
        var show_in_account_dropdowns: Bool?
        var custom_public_status: String?
        /// Prop Firm Mode rule columns (web propfirm page select).
        var consistency: FlexibleNumber?
        var max_drawdown: FlexibleNumber?
        var daily_drawdown: FlexibleNumber?
        var profit_target: FlexibleNumber?
        var winning_days: FlexibleNumber?
        var winning_day_threshold: FlexibleNumber?
        var payout_drawdown_behavior: String?
    }

    struct AccountWriteBody: Encodable, Sendable {
        var user_id: String?
        var name: String
        var account_size: String?
        var account_number: String?
        var category: String
        var mode: String
        var is_active: Bool?
        var can_add_trades: Bool?
        var note: String?
        var consistency: Double?
        var max_drawdown: Double?
        var daily_drawdown: Double?
        var profit_target: Double?
        var winning_days: Double?
        var winning_day_threshold: Double?
    }

    struct AccountSettingsBody: Encodable, Sendable {
        var show_in_account_dropdowns: Bool?
        var custom_public_status: String?
    }

    struct AccountPayoutEntryRow: Codable, Sendable {
        var id: String?
        var account_id: String?
        var user_id: String?
        var amount: FlexibleNumber?
        var payout_date: String?
        var note: String?
        var created_at: String?
        var updated_at: String?
    }

    struct AccountPayoutEntryWriteBody: Encodable, Sendable {
        var account_id: String
        var user_id: String
        var amount: Double
        var payout_date: String
        var note: String?
    }

    struct AccountPayoutEntryUpdateBody: Encodable, Sendable {
        var amount: Double?
        var payout_date: String?
        var note: String?
    }

    struct InsertBody: Encodable, Sendable {
        var user_id: String
        var account_id: String?
        var account_name: String?
        var account_size: String?
        var account_type: String?
        var account_category: String?
        var ticker: String
        var direction: String
        var mode: String?
        var contracts: Double
        var entry_price: Double?
        var exit_price: Double?
        var entry_time: String?
        var exit_time: String?
        var trade_date: String?
        var pnl: Double?
        var rr: Double?
        var points: Double?
        var session: String?
        var strategy: String?
        var notes: String?
        var image_url: String?
        var is_public: Bool
        var public_description: String?
        var confidence: Double?
        var emotion: String?
        var followed_plan: Bool?
        var market_condition: String?
        var timeframe: String?
        var news_event: Bool?
        var psychology_notes: String?
        var exit_emotion: String?
        var execution_rating: Int?
        var duration_seconds: Int?
        var duration_text: String?
        var image_display_mode: String?
        var created_at: String
        var date: String
        /// Web CSV imports set `is_initial_import` on bulk rows.
        var is_initial_import: Bool? = nil
        var import_source: String? = nil
        var import_fingerprint: String? = nil
    }

    /// Feed post created when a trade is shared publicly (web `posts` insert).
    struct TradePostInsertBody: Encodable, Sendable {
        var user_id: String
        var trade_id: String
        var image_url: String?
        var pnl: Double?
        var rr: Double?
        var caption: String
    }

    /// Mirrors web `InputTradeForm` save/update journal + psychology columns.
    struct UpdateBody: Encodable, Sendable {
        var account_id: String?
        var account_name: String?
        var account_size: String?
        var account_type: String?
        var account_category: String?
        var ticker: String
        var direction: String
        var mode: String?
        var contracts: Double
        var entry_price: Double?
        var exit_price: Double?
        var entry_time: String?
        var exit_time: String?
        var trade_date: String?
        var pnl: Double?
        var rr: Double?
        var points: Double?
        var session: String?
        var strategy: String?
        var notes: String?
        /// Explicit optional — always encoded (null clears screenshot like web `removeScreenshot`).
        var image_url: String?
        var is_public: Bool
        var public_description: String?
        var confidence: Double?
        var emotion: String?
        var followed_plan: Bool
        var market_condition: String?
        var timeframe: String?
        var news_event: Bool
        var psychology_notes: String?
        var exit_emotion: String?
        var execution_rating: Int?
        var duration_seconds: Int?
        var duration_text: String?
        var image_display_mode: String?
        var reviewed: Bool?
        var created_at: String

        enum CodingKeys: String, CodingKey {
            case account_id, account_name, account_size, account_type, account_category
            case ticker, direction, mode, contracts
            case entry_price, exit_price, entry_time, exit_time, trade_date
            case pnl, rr, points, session, strategy, notes, image_url
            case is_public, public_description, created_at
            case confidence, emotion, followed_plan, market_condition, timeframe, news_event
            case psychology_notes, exit_emotion, execution_rating, duration_seconds, duration_text, image_display_mode, reviewed
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(account_id, forKey: .account_id)
            try container.encodeIfPresent(account_name, forKey: .account_name)
            try container.encodeIfPresent(account_size, forKey: .account_size)
            try container.encodeIfPresent(account_type, forKey: .account_type)
            try container.encodeIfPresent(account_category, forKey: .account_category)
            try container.encode(ticker, forKey: .ticker)
            try container.encode(direction, forKey: .direction)
            try container.encodeIfPresent(mode, forKey: .mode)
            try container.encode(contracts, forKey: .contracts)
            try container.encodeIfPresent(entry_price, forKey: .entry_price)
            try container.encodeIfPresent(exit_price, forKey: .exit_price)
            try container.encodeIfPresent(entry_time, forKey: .entry_time)
            if let exit_time {
                try container.encode(exit_time, forKey: .exit_time)
            } else {
                try container.encodeNil(forKey: .exit_time)
            }
            try container.encodeIfPresent(trade_date, forKey: .trade_date)
            try container.encodeIfPresent(pnl, forKey: .pnl)
            if let rr {
                try container.encode(rr, forKey: .rr)
            } else {
                try container.encodeNil(forKey: .rr)
            }
            try container.encodeIfPresent(points, forKey: .points)
            try container.encodeIfPresent(session, forKey: .session)
            try container.encodeIfPresent(strategy, forKey: .strategy)
            try container.encodeIfPresent(notes, forKey: .notes)
            try container.encode(image_url, forKey: .image_url)
            try container.encode(is_public, forKey: .is_public)
            try container.encodeIfPresent(public_description, forKey: .public_description)
            if let confidence {
                try container.encode(confidence, forKey: .confidence)
            } else {
                try container.encodeNil(forKey: .confidence)
            }
            try container.encodeIfPresent(emotion, forKey: .emotion)
            try container.encode(followed_plan, forKey: .followed_plan)
            try container.encodeIfPresent(market_condition, forKey: .market_condition)
            try container.encodeIfPresent(timeframe, forKey: .timeframe)
            try container.encode(news_event, forKey: .news_event)
            try container.encodeIfPresent(psychology_notes, forKey: .psychology_notes)
            try container.encodeIfPresent(exit_emotion, forKey: .exit_emotion)
            if let execution_rating {
                try container.encode(execution_rating, forKey: .execution_rating)
            } else {
                try container.encodeNil(forKey: .execution_rating)
            }
            if let duration_seconds {
                try container.encode(duration_seconds, forKey: .duration_seconds)
            } else {
                try container.encodeNil(forKey: .duration_seconds)
            }
            if let duration_text {
                try container.encode(duration_text, forKey: .duration_text)
            } else {
                try container.encodeNil(forKey: .duration_text)
            }
            try container.encode(image_display_mode ?? TradeScreenshotDisplayMode.fit.rawValue, forKey: .image_display_mode)
            if let reviewed {
                try container.encode(reviewed, forKey: .reviewed)
            }
            try container.encode(created_at, forKey: .created_at)
        }
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
        var trading_style: String?
        var primary_market: String?
        var started_trading: String?
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
        var trading_style: String?
        var primary_market: String?
        var started_trading: String?
        var is_private: Bool?
    }

    struct DmPrivacyRow: Codable, Sendable {
        var dm_privacy: String?
    }

    struct DmPrivacyUpdateBody: Encodable, Sendable {
        var dm_privacy: String
    }

    struct OnboardingFields: Codable, Sendable {
        var id: String?
        var username: String?
        var name: String?
        var onboarding_completed: Bool?
        var trader_type: String?
        var trading_style: String?
        var started_trading: String?
        var bio: String?
        var avatar_url: String?
    }

    struct OnboardingCompletionBody: Encodable, Sendable {
        var username: String
        var name: String?
        var bio: String?
        var trading_style: String
        var trader_type: String
        var primary_market: String?
        var started_trading: String
        var avatar_url: String?
        var onboarding_completed: Bool
    }

    struct AccountSettingsOnboardingMirrorBody: Codable, Sendable {
        var id: String
        var onboarding_completed: Bool
    }

    struct UsernameAvailabilityParams: Encodable, Sendable {
        var check_username: String
    }

    struct UsernameAvailabilityResult: Decodable, Sendable {
        var result: Bool?
    }

    /// Idempotent profile shell when the auth trigger has not run yet.
    struct InsertBody: Encodable, Sendable {
        var id: String
        var username: String
        var name: String?
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

    /// Web Profile wall row from `profile_posts` (not the feed `posts` table).
    struct ProfileWallPost: Codable, Sendable {
        var id: String?
        var user_id: String?
        var content: String?
        var image_url: String?
        var created_at: String?
        var is_pinned: Bool?
        var profiles: EmbeddedAuthor?
    }

    /// Web feed join `profiles(username, avatar_url)` (+ optional `name`).
    struct EmbeddedAuthor: Codable, Sendable {
        var id: String?
        var username: String?
        var avatar_url: String?
        var name: String?

        init(id: String? = nil, username: String? = nil, avatar_url: String? = nil, name: String? = nil) {
            self.id = id
            self.username = username
            self.avatar_url = avatar_url
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            username = try container.decodeIfPresent(String.self, forKey: .username)
            avatar_url = try container.decodeIfPresent(String.self, forKey: .avatar_url)
            name = try container.decodeIfPresent(String.self, forKey: .name)
        }

        private enum CodingKeys: String, CodingKey {
            case id, username, avatar_url, name
        }
    }

    /// Web trade feed row — `posts` + `profiles` + optional `trades` embed (avoids N+1 trade SELECTs).
    struct TradeFeedRow: Codable, Sendable {
        var id: String?
        var user_id: String?
        var trade_id: String?
        var created_at: String?
        var image_url: String?
        var profiles: ProfilesBox?
        var trades: TradeEmbedBox?
    }

    /// PostgREST may return object or single-element array for many-to-one trade embeds.
    struct TradeEmbedBox: Codable, Sendable {
        var trade: TradeDTO.Trade?

        init(from decoder: Decoder) throws {
            if let single = try? TradeDTO.Trade(from: decoder) {
                trade = single
                return
            }
            trade = (try? [TradeDTO.Trade](from: decoder))?.first
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    /// Web profile feed row — `profile_posts` + profiles embed.
    struct ProfileFeedRow: Codable, Sendable {
        var id: String?
        var user_id: String?
        var content: String?
        var image_url: String?
        var created_at: String?
        var profiles: ProfilesBox?
    }

    /// Web reel feed row — `reels` + profiles embed.
    struct ReelFeedRow: Codable, Sendable {
        var id: String?
        var user_id: String?
        var caption: String?
        var video_url: String?
        var thumbnail_url: String?
        var duration_seconds: Int?
        var visibility: String?
        var trade_id: String?
        var created_at: String?
        var profiles: ProfilesBox?
    }

    /// Web achievement feed row — `achievement_posts` + profiles (+ nested achievement).
    struct AchievementFeedRow: Codable, Sendable {
        var id: String?
        var user_id: String?
        var achievement_id: String?
        var created_at: String?
        var profiles: ProfilesBox?
        var achievements: AchievementBox?
    }

    /// PostgREST may return object or single-element array for many-to-one embeds.
    struct ProfilesBox: Codable, Sendable {
        var profile: EmbeddedAuthor?

        init(from decoder: Decoder) throws {
            if let single = try? EmbeddedAuthor(from: decoder) {
                profile = single
                return
            }
            let many = try? [EmbeddedAuthor](from: decoder)
            profile = many?.first
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    struct AchievementBox: Codable, Sendable {
        var achievement: AchievementDTO.Achievement?

        init(from decoder: Decoder) throws {
            if let single = try? AchievementDTO.Achievement(from: decoder) {
                achievement = single
                return
            }
            let many = try? [AchievementDTO.Achievement](from: decoder)
            achievement = many?.first
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
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
    /// Web `DmConversationRow` shape from `fetchUserDmConversations`.
    struct Conversation: Codable, Sendable {
        var id: String?
        var is_group: Bool?
        var is_pinned: Bool?
        var name: String?
        var avatar_url: String?
        var last_message: String?
        var last_message_at: String?
        var participants: [Participant]?
    }

    struct Participant: Codable, Sendable {
        var user_id: String?
        var profiles: EmbeddedProfile?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            user_id = try container.decodeIfPresent(String.self, forKey: .user_id)
            if let single = try? container.decodeIfPresent(EmbeddedProfile.self, forKey: .profiles) {
                profiles = single
            } else if let many = try? container.decodeIfPresent([EmbeddedProfile].self, forKey: .profiles) {
                profiles = many.first
            } else {
                profiles = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(user_id, forKey: .user_id)
            try container.encodeIfPresent(profiles, forKey: .profiles)
        }

        private enum CodingKeys: String, CodingKey {
            case user_id, profiles
        }
    }

    struct EmbeddedProfile: Codable, Sendable {
        var id: String?
        var username: String?
        var avatar_url: String?
        var name: String?
    }

    struct MembershipRow: Codable, Sendable {
        var conversation_id: String?
        var user_id: String?
    }

    struct HiddenBlockedRow: Codable, Sendable {
        var conversation_id: String?
    }

    struct UnreadCountRow: Decodable, Sendable {
        var conversation_id: String?
        var unread_count: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            conversation_id = try container.decodeIfPresent(String.self, forKey: .conversation_id)
            if let int = try? container.decodeIfPresent(Int.self, forKey: .unread_count) {
                unread_count = int
            } else if let string = try? container.decodeIfPresent(String.self, forKey: .unread_count),
                      let parsed = Int(string)
            {
                unread_count = parsed
            } else if let double = try? container.decodeIfPresent(Double.self, forKey: .unread_count) {
                unread_count = Int(double)
            } else {
                unread_count = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case conversation_id, unread_count
        }
    }

    struct MutedPreferenceRow: Codable, Sendable {
        var conversation_id: String?
    }

    struct UserBlockRow: Codable, Sendable {
        var blocked_id: String?
        var created_at: String?
        var profiles: EmbeddedProfile?
    }

    struct BlockStatusRow: Codable, Sendable {
        var other_user_id: String?
        var blocked_by_me: Bool?
        var blocked_by_other: Bool?
    }

    struct MutedPeerRow: Codable, Sendable {
        var conversation_id: String?
        var peer_id: String?
        var username: String?
        var name: String?
        var avatar_url: String?
    }

    struct Message: Codable, Sendable {
        var id: String?
        var conversation_id: String?
        var sender_id: String?
        var sender_profile_id: String?
        var kind: String?
        /// Web `messages.type` (`text` / `trade` / …).
        var type: String?
        var body: String?
        var content: String?
        /// Web DM image column (`messages.image_url`).
        var image_url: String?
        var audio_url: String?
        var audio_duration_ms: Int?
        var trade_id: String?
        var created_at: String?
        var is_read: Bool?
        var deleted_for_everyone: Bool?
    }
}

nonisolated enum RoomDTO {
    struct Room: Codable, Sendable {
        var id: String?
        var owner_id: String?
        var owner_profile_id: String?
        var owner_user_id: String?
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
        var user_id: String?
        var type: String?
        var body: String?
        var content: String?
        var image_url: String?
        var audio_url: String?
        var audio_duration_ms: Int?
        var trade_id: String?
        var section_id: String?
        var parent_message_id: String?
        var created_at: String?
        var is_pinned: Bool?
        var room_message_reactions: [ReactionRow]?
    }

    struct ReactionRow: Codable, Sendable {
        var id: String?
        var message_id: String?
        var user_id: String?
        var reaction: String?
        var created_at: String?
    }

    /// Web `room_sections` — Trade Room channels.
    struct Channel: Codable, Sendable {
        var id: String?
        var room_id: String?
        var name: String?
        var position: Int?
        var allow_members_chat: Bool?
    }

    struct Membership: Codable, Sendable {
        var room_id: String?
        var user_id: String?
        var role: String?
        var joined_at: String?
    }

    /// Web Community `loadMemberRooms` row (`room_members` + rooms embed).
    struct MemberRoomRow: Decodable, Sendable {
        var room_id: String?
        var room: Room?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            room_id = try container.decodeIfPresent(String.self, forKey: .room_id)
            if let single = try? container.decodeIfPresent(Room.self, forKey: .room) {
                room = single
            } else if let many = try? container.decodeIfPresent([Room].self, forKey: .room) {
                room = many.first
            } else {
                room = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case room_id, room
        }
    }

    struct RoomUnreadCountRow: Decodable, Sendable {
        var room_id: String?
        var unread_count: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            room_id = try container.decodeIfPresent(String.self, forKey: .room_id)
            if let int = try? container.decodeIfPresent(Int.self, forKey: .unread_count) {
                unread_count = int
            } else if let string = try? container.decodeIfPresent(String.self, forKey: .unread_count),
                      let parsed = Int(string)
            {
                unread_count = parsed
            } else {
                unread_count = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case room_id, unread_count
        }
    }
}

nonisolated enum NotificationDTO {
    /// Columns used by web Activity (`app/notifications/page.tsx`) plus room FKs.
    static let selectColumns =
        "id,user_id,sender_id,type,post_id,trade_id,profile_post_id,achievement_post_id,reel_id,comment_id,room_id,room_message_id,content,read,created_at"

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
        var profile_post_id: String?
        var achievement_post_id: String?
        var reel_id: String?
        var comment_id: String?
        var room_id: String?
        var room_message_id: String?
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
    /// Exact web `ACHIEVEMENT_SELECT` (owner) — commas only, no whitespace variants required.
    static let ownerSelect =
        "id,user_id,achievement_type,title,description,badge_key,tier,category,value_numeric,value_text,currency,account_type,account_name,account_size,account_id,mode,firm,image_url,achieved_at,created_at,updated_at,is_featured,is_public,sort_order,metadata"

    /// Exact web `PUBLIC_ACHIEVEMENT_SELECT` (visitor) — omits account_name/size/id.
    static let publicSelect =
        "id,user_id,achievement_type,title,description,badge_key,tier,category,value_numeric,value_text,currency,account_type,mode,firm,image_url,achieved_at,created_at,updated_at,is_featured,is_public,sort_order,metadata"

    struct Achievement: Codable, Sendable {
        var id: String?
        var user_id: String?
        var achievement_type: String?
        var title: String?
        var description: String?
        var badge_key: String?
        var tier: String?
        var category: String?
        var value_numeric: FlexibleNumber?
        var value_text: String?
        var currency: String?
        var account_type: String?
        var account_name: String?
        var account_size: FlexibleNumber?
        var account_id: String?
        var mode: String?
        var firm: String?
        var image_url: String?
        var achieved_at: String?
        var created_at: String?
        var updated_at: String?
        var is_featured: Bool?
        var is_public: Bool?
        var sort_order: Int?
        var metadata: JSONVoid?
    }
}

/// Swallow arbitrary JSON (object/array/scalar) so optional jsonb columns never fail decoding.
nonisolated enum JSONVoid: Codable, Sendable, Equatable {
    case discarded

    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd {
                _ = try? unkeyed.decode(JSONVoid.self)
            }
            self = .discarded
            return
        }
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            for key in keyed.allKeys {
                _ = try? keyed.decode(JSONVoid.self, forKey: key)
            }
            self = .discarded
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .discarded
            return
        }
        _ = (try? single.decode(Bool.self))
            ?? (try? single.decode(Double.self)).map { _ in true }
            ?? (try? single.decode(String.self)).map { _ in true }
        self = .discarded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
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
        /// Not present on current BFF/RPC payloads — decoded when backend adds profile embed.
        var username: String?
        var name: String?
        var avatar_url: String?
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
