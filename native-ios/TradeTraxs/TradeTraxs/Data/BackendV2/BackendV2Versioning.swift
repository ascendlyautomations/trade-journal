import Foundation

/// Backend V2 RPC naming + contract version metadata (Phase 1 — no SQL yet).
nonisolated enum BackendV2Versioning {
    static let contractVersion = "v1"

    enum RPCName: String, CaseIterable, Sendable {
        case session = "rpc_v1_session_bootstrap"
        case dashboard = "rpc_v1_dashboard_bootstrap"
        case viewerSyncState = "rpc_v1_viewer_sync_state"
        case feed = "rpc_v1_feed_bootstrap"
        case profile = "rpc_v1_profile_bootstrap"
        case profileTabTrades = "rpc_v1_profile_tab_trades"
        case profileTabTradesV2 = "rpc_v1_profile_tab_trades_v2"
        case profileTabTradesSummaryShadowCompare =
            "rpc_v1_profile_tab_trades_summary_shadow_compare"
        case profileTabPosts = "rpc_v1_profile_tab_posts"
        case profileTabReels = "rpc_v1_profile_tab_reels"
        case profileTabAchievements = "rpc_v1_profile_tab_achievements"
        case profileStatisticsBootstrap = "rpc_v1_profile_statistics_bootstrap"
        case profileAnalyticsBootstrapV2 = "rpc_v1_profile_analytics_bootstrap_v2"
        case profilePublicAnalyticsRevision = "rpc_v1_profile_public_analytics_revision"
        case profilePinContent = "rpc_v1_profile_pin_content"
        case profileUnpinContent = "rpc_v1_profile_unpin_content"
        case profileReorderPinned = "rpc_v1_profile_reorder_pinned"
        case messaging = "rpc_v2_messaging_bootstrap"
        case conversation = "rpc_v1_conversation_bootstrap"
        case conversationThread = "rpc_v1_conversation_thread_bootstrap"
        case room = "rpc_v1_room_bootstrap"
        case publicRoomGuest = "rpc_v1_public_room_guest_bootstrap"
        case activity = "rpc_v1_activity_bootstrap"
        case explore = "rpc_v1_explore_bootstrap"
        case tradeRoomDiscovery = "rpc_v1_trade_room_discovery"
        case tradeRoomsHomeBootstrap = "rpc_v1_trade_rooms_home_bootstrap"
        case tradeRoomSearch = "rpc_v1_search_trade_rooms"
        case leaderboard = "rpc_v1_leaderboard_bootstrap"
        case calendar = "rpc_v1_calendar_bootstrap"
        case analyticsDailyRangeBootstrap = "rpc_v1_analytics_daily_range_bootstrap"
        case analyticsCalendarDayTrades = "rpc_v1_analytics_calendar_day_trades"
        case analyticsDashboardBootstrapV3 = "rpc_v1_analytics_dashboard_bootstrap_v3"
        case analyticsDashboardAccountChartsV3 = "rpc_v1_analytics_dashboard_account_charts_v3"
        case analyticsDashboardAggregateChartsV3 = "rpc_v1_analytics_dashboard_aggregate_charts_v3"
        case analyticsRevision = "rpc_v1_analytics_revision"
        case tradesList = "rpc_v1_trades_list_bootstrap"
        case tradesListV2 = "rpc_v1_trades_list_bootstrap_v2"
        case tradeDetail = "rpc_v1_trade_detail_bootstrap"
        case tradeDetailOwnerComparison = "rpc_v1_trade_detail_owner_comparison"
        case postDetail = "rpc_v1_post_detail_bootstrap"
        case settings = "rpc_v1_settings_bootstrap"
        case propFirm = "rpc_v1_prop_firm_bootstrap"
        case gettingStarted = "rpc_v1_getting_started_signals"
        case psychologyCheckInWindow = "rpc_v1_psychology_check_in_window"
        case checkInHistoryBootstrap = "rpc_v1_check_in_history_bootstrap"
    }

    static func isKnownRPCName(_ name: String) -> Bool {
        RPCName(rawValue: name) != nil
    }

    static func assertContractVersion(_ version: String?) throws {
        guard version == contractVersion else {
            throw BackendV2RPCError.contractVersionMismatch(
                expected: contractVersion,
                got: version ?? "missing"
            )
        }
    }
}

nonisolated struct BootstrapMetaV1: Codable, Sendable, Equatable {
    var contract_version: String
    var server_time: String
    var viewer_id: String?
}
