import Foundation

// MARK: - Shared cards

nonisolated struct ViewerCardV1: Codable, Sendable, Equatable {
    var id: String
    var username: String?
    var display_name: String?
    var avatar_url: String?
    var is_private: Bool
    var onboarding_flags: [String: Bool]
    var entitlement: EntitlementV1
}

nonisolated struct EntitlementV1: Codable, Sendable, Equatable {
    var plan: String
    var status: String?
    var flags: [String: Bool]
}

nonisolated struct AccountSummaryV1: Codable, Sendable, Equatable {
    var id: String
    var name: String?
    var type: String?
    var currency: String?
    var is_active: Bool
}

nonisolated struct BadgeCountsV1: Codable, Sendable, Equatable {
    var notifications_unread: Int
    var dm_unread: Int
    var rooms_unread: Int?
}

nonisolated struct AuthorCardV1: Codable, Sendable, Equatable {
    var id: String
    var username: String?
    var display_name: String?
    var avatar_url: String?
    var is_verified: Bool?
}

nonisolated struct EngagementSnapshotV1: Codable, Sendable, Equatable {
    var like_count: Int
    var comment_count: Int
    var liked_by_viewer: Bool
}

nonisolated struct FollowEdgeV1: Codable, Sendable, Equatable {
    var is_following: Bool
    var is_followed_by: Bool
    var request_pending: Bool
    var follower_count: Int
    var following_count: Int
}

// MARK: - Bootstraps

nonisolated struct SessionBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var viewer: ViewerCardV1
        var session_profile: SessionProfileV1
        var accounts_summary: [AccountSummaryV1]
        var following_ids: [String]
        var badges: BadgeCountsV1
        var prefs_min: PrefsMin
        var realtime: RealtimeHints

        nonisolated struct PrefsMin: Codable, Sendable, Equatable {
            var notifications_enabled_summary: Bool
            var messaging_defaults: [String: JSONValue]
        }

        nonisolated struct RealtimeHints: Codable, Sendable, Equatable {
            var channels: [String]
        }
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct SessionProfileV1: Codable, Sendable, Equatable {
    var id: String
    var username: String?
    var avatar_url: String?
    var is_pro: Bool?
    var creator_access: Bool?
    var subscription_status: String?
    var trial_end: String?
    var stripe_customer_id: String?
    var signup_flow_source: String?
    var early_access_enrolled_at: String?
    var early_access_started_at: String?
    var early_access_ends_at: String?
    var early_access_status: String?
    var early_access_campaign_id: String?
    var early_access_enrollment_source: String?
    var lifetime_access_source: String?
    var lifetime_access_granted_at: String?
    var is_banned: Bool?
    var banned_reason: String?
    var referral_code: String?
    var is_beta_tester: Bool?
    var use_free_tier: Bool?
    var onboarding_completed: Bool?
    var has_seen_getting_started_intro: Bool?
    var has_seen_onboarding_complete_popup: Bool?
    var bio: String?
    var trading_style: String?
    var trader_type: String?
    var primary_market: String?
    var started_trading: String?
    var max_drawdown_limit: Double?
    var is_private: Bool?
    var has_email_password: Bool?
}

nonisolated struct DashboardAccountV1: Codable, Sendable, Equatable {
    var id: String
    var account_number: JSONValue?
    var name: String?
    var account_size: PostgresAccountSizeWire?
    var mode: String?
    var category: String?
    var is_active: PostgresFlexibleBool?
    var can_add_trades: PostgresFlexibleBool?
    var note: String?
    var consistency: PostgresFlexibleDouble?
    var max_drawdown: PostgresFlexibleDouble?
    var daily_drawdown: PostgresFlexibleDouble?
    var profit_target: PostgresFlexibleDouble?
    var winning_days: PostgresFlexibleDouble?
    var winning_day_threshold: PostgresFlexibleDouble?
    var type: String?
    var currency: String?
}

nonisolated struct DashboardBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var accounts: [DashboardAccountWireV1]
        var trade_window: [DashboardTradeWireV1]
        var trade_window_meta: TradeWindowMeta
        var metrics: DashboardMetricsWireV1
        var equity_points: [DashboardEquityPointWireV1]
        var payout_total: PostgresFlexibleDouble?
        var recent_trades: [DashboardRecentTradeWireV1]

        nonisolated struct TradeWindowMeta: Codable, Sendable, Equatable {
            var limit: Int
            var returned: Int
            var history_complete: Bool
            var total_trade_count: Int
            var oldest_created_at: String?
            var next_cursor: String?
        }
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }

    func validateContract() throws {
        try validateContractVersion()
        guard data.trade_window_meta.limit >= 1 else {
            throw BackendV2RPCError.decode("trade_window_meta.limit invalid")
        }
    }
}

nonisolated struct FeedItemV1: Codable, Sendable, Equatable {
    var kind: String
    var id: String
    var created_at: String
    var author_id: String
    var payload: [String: JSONValue]
}

nonisolated struct FeedStoryPreviewV1: Codable, Sendable, Equatable {
    var id: String
    var user_id: String
    var image_url: String
    var created_at: String
}

nonisolated struct FeedPageMetaV1: Codable, Sendable, Equatable {
    var limit: Int
    var returned: Int
    var has_more: Bool
}

nonisolated struct FeedBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var scope: String
        var content_filter: String
        var items: [FeedItemV1]
        var authors: [String: AuthorCardV1]
        var engagement: [String: EngagementSnapshotV1]
        var stories: [FeedStoryPreviewV1]
        var story_authors: [String: AuthorCardV1]
        var next_cursor: String?
        var page_meta: FeedPageMetaV1
        var following_ids_echo: [String]
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct ProfileBootstrapV1: Codable, Sendable, Equatable {
    var meta: ProfileBootstrapMetaV1
    var data: DataPayload

    nonisolated struct ProfileBootstrapMetaV1: Codable, Sendable, Equatable {
        var contract_version: String
        var found: Bool?
        var server_time: String?
        var viewer_id: String?
    }

    nonisolated struct ProfileHeaderWire: Codable, Sendable, Equatable {
        var id: String
        var username: String?
        var name: String?
        var bio: String?
        var avatar_url: String?
        var trading_style: String?
        var trader_type: String?
        var primary_market: String?
        var started_trading: String?
        var is_private: Bool?
        var created_at: String?
    }

    nonisolated struct ViewerWire: Codable, Sendable, Equatable {
        var is_own_profile: Bool
        var can_view_trades: Bool
        var is_following: Bool
        var is_requested: Bool
        var follows_you: Bool
    }

    nonisolated struct PublicStatsWire: Codable, Sendable, Equatable {
        var total_trades: Int?
        var wins: Int?
        var total_pnl: PostgresFlexibleDouble?
        /// Gross winning P&L / abs(gross losing P&L); null when there are no losses.
        var profit_factor: PostgresFlexibleDouble?
        /// Mean `rr` across eligible public trades; null when no RR values exist.
        var average_rr: PostgresFlexibleDouble?
        /// Sum of viewer-visible payout achievement values — web `sumPayoutAchievementTotals`.
        var payout_total: PostgresFlexibleDouble?
    }

    nonisolated struct OwnedRoomWire: Codable, Sendable, Equatable {
        var id: String
        var name: String?
        var slug: String?
        var show_on_profile: Bool?
    }

    nonisolated struct TradesPageWire: Codable, Sendable, Equatable {
        var items: [DashboardTradeWireV1]
        var page_meta: PageMeta

        nonisolated struct PageMeta: Codable, Sendable, Equatable {
            var limit: Int
            var returned: Int
            var has_more: Bool
            var next_cursor: String?
        }
    }

    nonisolated struct TradeEngagementWire: Codable, Sendable, Equatable {
        var like_count: Int
        var liked_by_me: Bool
        var comment_count: Int
    }

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var profile: ProfileHeaderWire?
        var viewer: ViewerWire
        var followers_count: Int
        var following_count: Int
        var section_counts: [String: JSONValue]?
        var public_stats: PublicStatsWire?
        var owned_room: OwnedRoomWire?
        var active_tab: String?
        var trades_page: TradesPageWire?
        var trade_engagement: [String: TradeEngagementWire]?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct MessagesBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    /// Messaging inbox only — Rooms are a separate domain.
    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var conversations: [MessagingConversationV1]
        var peers: [String: AuthorCardV1]
        /// Messaging computes; Session stores for badges.
        var dm_unread_total: Int
        var muted_ids: [String]
        var next_cursor: String?
        var page_meta: PageMeta

        nonisolated struct PageMeta: Codable, Sendable, Equatable {
            var limit: Int
            var returned: Int
            var has_more: Bool
        }
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct MessagingConversationV1: Codable, Sendable, Equatable {
    var id: String
    var is_group: Bool
    var is_pinned: Bool
    var name: String?
    var avatar_url: String?
    var last_message_id: String?
    var last_message_sender_id: String?
    var last_message_type: String?
    var last_message: String?
    var last_message_at: String?
    var unread_count: Int
    var muted: Bool
    var participants: [MessagingParticipantV1]
}

nonisolated struct MessagingParticipantV1: Codable, Sendable, Equatable {
    var user_id: String
    var username: String?
    var display_name: String?
    var avatar_url: String?
}

nonisolated struct RoomsBootstrapV1: Codable, Sendable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct RoomSectionWire: Codable, Sendable, Equatable {
        var id: String
        var room_id: String
        var name: String
        var position: Int
        var allow_members_chat: Bool
    }

    nonisolated struct RoomShellWire: Codable, Sendable, Equatable {
        var id: String
        var name: String?
        var description: String?
        var slug: String?
        var image_url: String?
        var owner_user_id: String?
        var show_on_profile: Bool?
        var created_at: String?
    }

    nonisolated struct MembershipWire: Codable, Sendable, Equatable {
        var notification_enabled: Bool
        var is_owner: Bool
    }

    nonisolated struct MemberStatsWire: Codable, Sendable, Equatable {
        var total_members: Int
        var active_members: Int
        var left_members: Int
    }

    nonisolated struct MarkReadWire: Codable, Sendable, Equatable {
        var applied: Bool
    }

    nonisolated struct DataPayload: Codable, Sendable {
        var room: RoomShellWire
        var membership: MembershipWire
        var sections: [RoomSectionWire]
        var active_section_id: String?
        var channel_preferences: [String: Bool]?
        var member_stats: MemberStatsWire?
        var unread_count: Int
        var mark_read: MarkReadWire
        var pinned_messages: [RoomDTO.Message]
        var messages: [RoomDTO.Message]
        var has_more_messages: Bool
        var next_message_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct PropFirmAccountWireV1: Codable, Sendable, Equatable {
    var id: String
    var name: String?
    var account_size: PostgresAccountSizeWire?
    var account_number: PostgresAccountSizeWire?
    var mode: String?
    var consistency: PostgresFlexibleDouble?
    var max_drawdown: PostgresFlexibleDouble?
    var daily_drawdown: PostgresFlexibleDouble?
    var profit_target: PostgresFlexibleDouble?
    var winning_days: PostgresFlexibleDouble?
    var winning_day_threshold: PostgresFlexibleDouble?
    var payout_drawdown_behavior: String?
    var remember_payout_drawdown_behavior: PostgresFlexibleBool?

    func asAccountDTO(ownerID: String) -> TradeDTO.Account {
        TradeDTO.Account(
            id: id,
            user_id: ownerID,
            name: name,
            account_name: nil,
            account_type: "Prop Firm",
            category: "Prop Firm",
            mode: mode,
            account_size: account_size.map { FlexibleNumber($0.decimal) },
            size: nil,
            account_number: account_number?.raw,
            note: nil,
            is_active: true,
            can_add_trades: true,
            show_in_account_dropdowns: nil,
            custom_public_status: nil,
            consistency: consistency.map { FlexibleNumber($0.decimal) },
            max_drawdown: max_drawdown.map { FlexibleNumber($0.decimal) },
            daily_drawdown: daily_drawdown.map { FlexibleNumber($0.decimal) },
            profit_target: profit_target.map { FlexibleNumber($0.decimal) },
            winning_days: winning_days.map { FlexibleNumber($0.decimal) },
            winning_day_threshold: winning_day_threshold.map { FlexibleNumber($0.decimal) },
            payout_drawdown_behavior: payout_drawdown_behavior
        )
    }
}

nonisolated struct PropFirmTradeWireV1: Codable, Sendable, Equatable {
    var id: String
    var account_id: String?
    var pnl: PostgresFlexibleDouble?
    var date: String?
    var trade_date: String?
    var entry_time: String?
    var exit_time: String?
    var created_at: String?

    func asTradeDTO(ownerID: String) -> TradeDTO.Trade {
        TradeDTO.Trade(
            id: id,
            user_id: ownerID,
            account_id: account_id,
            ticker: nil,
            direction: nil,
            mode: nil,
            account_type: nil,
            contracts: nil,
            entry_price: nil,
            exit_price: nil,
            entry_time: entry_time,
            exit_time: exit_time,
            pnl: pnl.map { FlexibleNumber($0.decimal) },
            rr: nil,
            points: nil,
            session: nil,
            is_public: nil,
            is_pinned: nil,
            public_description: nil,
            image_url: nil,
            notes: nil,
            created_at: created_at,
            date: date,
            trade_date: trade_date,
            account_name: nil,
            strategy: nil
        )
    }
}

nonisolated struct PropFirmBootstrapV1: Codable, Sendable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable {
        var accounts: [PropFirmAccountWireV1]
        var payout_cycles: [JSONValue]
        var achievements: [JSONValue]
        var trades: [PropFirmTradeWireV1]
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct ActivityNotificationWireV1: Codable, Sendable, Equatable {
    var id: String?
    var user_id: String?
    var sender_id: String?
    var type: String?
    var post_id: String?
    var trade_id: String?
    var profile_post_id: String?
    var achievement_post_id: String?
    var reel_id: String?
    var comment_id: String?
    var room_id: String?
    var room_message_id: String?
    var content: String?
    var read: Bool?
    var created_at: String?

    func asNotificationDTO() -> NotificationDTO.Item {
        NotificationDTO.Item(
            id: id,
            type: type,
            kind: nil,
            user_id: user_id,
            sender_id: sender_id,
            actor_profile_id: nil,
            title: nil,
            content: content,
            body: nil,
            created_at: created_at,
            read: read,
            is_read: nil,
            trade_id: trade_id,
            post_id: post_id,
            profile_post_id: profile_post_id,
            achievement_post_id: achievement_post_id,
            reel_id: reel_id,
            comment_id: comment_id,
            room_id: room_id,
            room_message_id: room_message_id
        )
    }
}

nonisolated struct ActivityFollowRequestWireV1: Codable, Sendable, Equatable {
    var id: String
    var requester_id: String
    var created_at: String?
}

nonisolated struct ActivityBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var notifications: [ActivityNotificationWireV1]
        var actors: [String: AuthorCardV1]
        var follow_requests: [ActivityFollowRequestWireV1]
        var unread_total: Int
        var next_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct ExploreTraderWireV1: Codable, Sendable, Equatable {
    var id: String
    var username: String?
    var name: String?
    var bio: String?
    var avatar_url: String?
    var trader_type: String?
    var trading_style: String?
    var primary_market: String?
    var started_trading: String?
    var is_private: Bool?
    var created_at: String?
}

nonisolated struct ExploreRoomWireV1: Codable, Sendable, Equatable {
    var id: String
    var name: String?
    var description: String?
    var slug: String?
    var member_count: PostgresFlexibleInt?
    var image_url: String?
}

nonisolated struct ExploreActivityMetaWireV1: Codable, Sendable, Equatable {
    var trade_count: Int?
    var last_trade_at: String?
}

nonisolated struct ExploreBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct SocialCount: Codable, Sendable, Equatable {
        var followers: Int
        var following: Int
    }

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var traders: [ExploreTraderWireV1]
        var rooms: [ExploreRoomWireV1]
        var social_counts: [String: SocialCount]
        var following_ids: [String]
        var activity_meta: [String: ExploreActivityMetaWireV1]
        var traders_next_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct LeaderboardBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var timeframe: String
        var category: String
        var rows: [JSONValue]
        var next_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct CalendarBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var year: Int
        var month: Int
        var accounts: [DashboardAccountWireV1]
        var trades: [DashboardTradeWireV1]
        var metrics_month: CalendarMetricsWireV1?
    }

    nonisolated struct CalendarMetricsWireV1: Codable, Sendable, Equatable {
        var net_pnl: PostgresFlexibleDouble?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct TradesListBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct PageMeta: Codable, Sendable, Equatable {
        var limit: Int
        var returned: Int
        var has_more: Bool
    }

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var accounts: [DashboardAccountWireV1]
        var trades: [DashboardTradeWireV1]
        var next_cursor: String?
        var page_meta: PageMeta
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct TradeDetailBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var trade: JSONValue
        var author: AuthorCardV1
        var engagement: EngagementSnapshotV1
        var comments_page: [JSONValue]?
        var viewer_state: [String: JSONValue]
        var next_comments_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct SettingsBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var profile_settings: [String: JSONValue]
        var notification_prefs: [String: JSONValue]
        var messaging_prefs: [String: JSONValue]
        var accounts: [AccountSummaryV1]
        var entitlement: EntitlementV1
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

/// Minimal JSON value tree for flexible contract slices.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSONValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
