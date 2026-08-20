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
    var account_size: Double?
    var mode: String?
    var category: String?
    var is_active: Bool?
    var can_add_trades: Bool?
    var note: String?
    var consistency: Double?
    var max_drawdown: Double?
    var daily_drawdown: Double?
    var profit_target: Double?
    var winning_days: Double?
    var winning_day_threshold: Double?
    var type: String?
    var currency: String?
}

nonisolated struct DashboardBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var accounts: [DashboardAccountV1]
        var trade_window: [JSONValue]
        var trade_window_meta: TradeWindowMeta
        var metrics: [String: JSONValue]
        var equity_points: [EquityPoint]
        var payout_total: Double?
        var recent_trades: [JSONValue]

        nonisolated struct TradeWindowMeta: Codable, Sendable, Equatable {
            var limit: Int
            var returned: Int
            var history_complete: Bool
            var total_trade_count: Int
            var oldest_created_at: String?
            var next_cursor: String?
        }

        nonisolated struct EquityPoint: Codable, Sendable, Equatable {
            var t: String
            var v: Double
        }
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
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
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var profile: ProfileCard
        var stats: [String: JSONValue]
        var follow_edge: FollowEdgeV1
        var owned_room: OwnedRoom?
        var tab_availability: TabAvailability

        nonisolated struct ProfileCard: Codable, Sendable, Equatable {
            var id: String
            var username: String?
            var display_name: String?
            var avatar_url: String?
            var is_verified: Bool?
            var bio: String?
            var is_private: Bool
            var trader_type: String?
        }

        nonisolated struct OwnedRoom: Codable, Sendable, Equatable {
            var id: String
            var name: String?
        }

        nonisolated struct TabAvailability: Codable, Sendable, Equatable {
            var trades: Bool
            var posts: Bool
            var reels: Bool
            var achievements: Bool
        }
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

nonisolated struct RoomsBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var room: JSONValue
        var membership: JSONValue?
        var messages: [JSONValue]
        var sections: [JSONValue]?
        var unread: Int
        var peers: [String: AuthorCardV1]
        var next_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct ActivityBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var notifications: [JSONValue]
        var actors: [String: AuthorCardV1]
        var follow_requests: [JSONValue]
        var unread_total: Int
        var next_cursor: String?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

nonisolated struct ExploreBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var traders: [JSONValue]
        var rooms: [JSONValue]
        var social_counts: [String: SocialCount]
        var following_ids: [String]
        var activity_meta: [String: JSONValue]

        nonisolated struct SocialCount: Codable, Sendable, Equatable {
            var followers: Int
            var following: Int
        }
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
        var accounts: [AccountSummaryV1]
        var day_buckets: [JSONValue]
        var trades_by_day: [String: [JSONValue]]
        var metrics_month: [String: JSONValue]
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
