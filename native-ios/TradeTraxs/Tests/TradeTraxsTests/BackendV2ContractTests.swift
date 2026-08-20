import XCTest
@testable import TradeTraxs

final class BackendV2ContractTests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2Telemetry.setSink(nil)
        super.tearDown()
    }

    func testAllFeatureFlagsDefaultOff() {
        let flags = BackendV2FeatureFlags.allFlags()
        XCTAssertEqual(flags.count, 12)
        for entry in flags {
            XCTAssertFalse(entry.enabled, entry.name)
            XCTAssertFalse(BackendV2FeatureFlags.isEnabled(entry.flag))
        }
    }

    func testFeatureFlagTestOverrideResets() {
        BackendV2FeatureFlags.setFlagForTests(.feed, enabled: true)
        XCTAssertTrue(BackendV2FeatureFlags.isEnabled(.feed))
        BackendV2FeatureFlags.resetFlagsForTests()
        XCTAssertFalse(BackendV2FeatureFlags.isEnabled(.feed))
    }

    func testSessionBootstrapJSONDecode() throws {
        let value: SessionBootstrapV1 = try decodeFixture(
            BackendV2ContractFixtures.session
        )
        try value.validateContractVersion()
        XCTAssertEqual(value.data.viewer.username, "viewer")
        XCTAssertEqual(value.data.following_ids.count, 1)
        XCTAssertEqual(value.data.badges.notifications_unread, 2)
    }

    func testFeedBootstrapJSONDecode() throws {
        let value: FeedBootstrapV1 = try decodeFixture(
            BackendV2ContractFixtures.feed
        )
        try value.validateContractVersion()
        XCTAssertEqual(value.data.items.count, 1)
        XCTAssertEqual(value.data.scope, "following")
    }

    func testDashboardBootstrapJSONDecode() throws {
        let value: DashboardBootstrapV1 = try decodeFixture(
            BackendV2ContractFixtures.dashboard
        )
        try value.validateContractVersion()
        XCTAssertEqual(value.data.accounts.count, 1)
    }

    func testProfileBootstrapJSONDecode() throws {
        let value: ProfileBootstrapV1 = try decodeFixture(
            BackendV2ContractFixtures.profile
        )
        try value.validateContractVersion()
        XCTAssertTrue(value.data.follow_edge.is_following)
    }

    func testMessagesRoomsActivityExploreLeaderboardCalendarDetailSettingsDecode() throws {
        let _: MessagesBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.messages)
        let _: RoomsBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.rooms)
        let _: ActivityBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.activity)
        let _: ExploreBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.explore)
        let _: LeaderboardBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.leaderboard)
        let _: CalendarBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.calendar)
        let _: TradeDetailBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.tradeDetail)
        let _: SettingsBootstrapV1 = try decodeFixture(BackendV2ContractFixtures.settings)
    }

    func testContractVersionMismatchThrows() {
        let bad = BackendV2ContractFixtures.session.replacingOccurrences(
            of: "\"v1\"",
            with: "\"v0\""
        )
        do {
            let value: SessionBootstrapV1 = try decodeFixture(bad)
            XCTAssertThrowsError(try value.validateContractVersion())
        } catch {
            XCTFail("Decode should succeed; validation should fail: \(error)")
        }
    }

    func testRPCClientTypedDecodeAndTelemetry() async throws {
        var events: [BackendV2TelemetryEvent] = []
        BackendV2Telemetry.setEnabled(true)
        BackendV2Telemetry.setSink { events.append($0) }

        let transport = FixtureRPCClient(json: BackendV2ContractFixtures.session)
        let client = BackendV2RPCClient(transport: transport)
        let value = try await client.call(
            .session,
            as: SessionBootstrapV1.self,
            options: BackendV2RPCCallOptions(cacheMiss: true, flagName: "backendV2.session")
        )
        try value.validateContractVersion()
        XCTAssertEqual(value.data.viewer.username, "viewer")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].rpcName, BackendV2Versioning.RPCName.session.rawValue)
        XCTAssertTrue(events[0].success)
        XCTAssertEqual(events[0].cacheMiss, true)
        XCTAssertNotNil(events[0].payloadBytes)
        XCTAssertNotNil(events[0].decodeMs)
    }

    func testRPCClientRejectsUnknownName() async {
        let transport = FixtureRPCClient(json: "{}")
        let client = BackendV2RPCClient(transport: transport)
        do {
            let _: SessionBootstrapV1 = try await client.call(
                "not_a_backend_v2_rpc",
                as: SessionBootstrapV1.self
            )
            XCTFail("Expected unknown RPC error")
        } catch let error as BackendV2RPCError {
            XCTAssertEqual(error.code, "validation")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnimplementedRpcAdapterThrows() async {
        let stub = UnimplementedRpcBootstrapRepository()
        do {
            _ = try await stub.loadDashboardBootstrap(accountID: nil)
            XCTFail("Expected notImplemented")
        } catch let error as BackendV2RPCError {
            XCTAssertEqual(error.code, "not_implemented")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testKnownRPCNamesMatchWebConventions() {
        XCTAssertEqual(
            BackendV2Versioning.RPCName.session.rawValue,
            "rpc_v1_session_bootstrap"
        )
        XCTAssertEqual(
            BackendV2Versioning.RPCName.feed.rawValue,
            "rpc_v1_feed_bootstrap"
        )
        XCTAssertTrue(BackendV2Versioning.isKnownRPCName("rpc_v1_settings_bootstrap"))
    }

    private func decodeFixture<T: Decodable>(_ json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// In-memory RPC transport for Backend V2 contract tests.
private struct FixtureRPCClient: RPCClient {
    let json: String

    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        _ = (functionName, parameters)
        return Data(json.utf8)
    }

    func call(functionName: String, jsonBody: Data) async throws -> Data {
        _ = (functionName, jsonBody)
        return Data(json.utf8)
    }
}

/// Golden fixtures — keep in sync with `lib/backendV2/fixtures.ts`.
enum BackendV2ContractFixtures {
    static let session = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"viewer":{"id":"11111111-1111-1111-1111-111111111111","username":"viewer","display_name":"Viewer","avatar_url":null,"is_private":false,"onboarding_flags":{"completed":true},"entitlement":{"plan":"pro","status":"active","flags":{"early_access":false}}},"session_profile":{"id":"11111111-1111-1111-1111-111111111111","username":"viewer","avatar_url":null,"is_pro":true,"creator_access":false,"subscription_status":"active","trial_end":null,"stripe_customer_id":null,"signup_flow_source":"standard_email","early_access_enrolled_at":null,"early_access_started_at":null,"early_access_ends_at":null,"early_access_status":null,"early_access_campaign_id":null,"early_access_enrollment_source":null,"lifetime_access_source":null,"lifetime_access_granted_at":null,"is_banned":false,"banned_reason":null,"referral_code":"VIEWER1","is_beta_tester":false,"use_free_tier":false,"onboarding_completed":true,"has_seen_getting_started_intro":true,"has_seen_onboarding_complete_popup":true,"bio":null,"trading_style":null,"trader_type":"day","primary_market":null,"started_trading":null,"max_drawdown_limit":null,"is_private":false,"has_email_password":true},"accounts_summary":[{"id":"33333333-3333-3333-3333-333333333333","name":"Main","type":"live","currency":"USD","is_active":true}],"following_ids":["22222222-2222-2222-2222-222222222222"],"badges":{"notifications_unread":2,"dm_unread":1,"rooms_unread":0},"prefs_min":{"notifications_enabled_summary":true,"messaging_defaults":{}},"realtime":{"channels":["notifications","messages"]}}}
    """

    static let dashboard = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":"33333333-3333-3333-3333-333333333333","account_number":1,"name":"Main","account_size":50000,"mode":"live","category":"personal","is_active":true,"can_add_trades":true}],"trade_window":[{"id":"t1","pnl":100}],"trade_window_meta":{"limit":500,"returned":1,"history_complete":true,"total_trade_count":1,"oldest_created_at":"2026-08-01T00:00:00.000Z","next_cursor":null},"metrics":{"win_rate":0.55,"net_pnl":100,"total_trades":1},"equity_points":[{"t":"2026-08-01","v":1000}],"payout_total":0,"recent_trades":[{"id":"t1"}]}}
    """

    static let feed = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"scope":"following","content_filter":"all","items":[{"kind":"post","id":"p1","created_at":"2026-08-19T20:00:00.000Z","author_id":"22222222-2222-2222-2222-222222222222","payload":{"caption":"hello"}}],"authors":{"22222222-2222-2222-2222-222222222222":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null}},"engagement":{"p1":{"like_count":3,"comment_count":1,"liked_by_viewer":false}},"stories":[],"story_authors":{},"next_cursor":null,"page_meta":{"limit":8,"returned":1,"has_more":false},"following_ids_echo":["22222222-2222-2222-2222-222222222222"]}}
    """

    static let profile = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"profile":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null,"bio":"bio","is_private":false,"trader_type":"day"},"stats":{"trades":10,"followers":5},"follow_edge":{"is_following":true,"is_followed_by":false,"request_pending":false,"follower_count":5,"following_count":2},"owned_room":null,"tab_availability":{"trades":true,"posts":true,"reels":true,"achievements":true}}}
    """

    static let messages = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"conversations":[{"id":"c1111111-1111-1111-1111-111111111111","is_group":false,"is_pinned":false,"name":null,"avatar_url":null,"last_message":"hey","last_message_at":"2026-08-19T19:00:00.000Z","unread_count":1,"muted":false,"participants":[{"user_id":"11111111-1111-1111-1111-111111111111","username":"viewer","display_name":"Viewer","avatar_url":null},{"user_id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null}]}],"peers":{"22222222-2222-2222-2222-222222222222":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null}},"dm_unread_total":1,"muted_ids":[],"next_cursor":null,"page_meta":{"limit":40,"returned":1,"has_more":false}}}
    """

    static let rooms = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"room":{"id":"r1","name":"Room"},"membership":{"role":"member"},"messages":[{"id":"m1"}],"sections":null,"unread":0,"peers":{"22222222-2222-2222-2222-222222222222":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null}},"next_cursor":null}}
    """

    static let activity = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"notifications":[{"id":"n1","type":"like"}],"actors":{"22222222-2222-2222-2222-222222222222":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null}},"follow_requests":[],"unread_total":2,"next_cursor":null}}
    """

    static let explore = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"traders":[{"id":"22222222-2222-2222-2222-222222222222"}],"rooms":[],"social_counts":{"22222222-2222-2222-2222-222222222222":{"followers":5,"following":2}},"following_ids":["22222222-2222-2222-2222-222222222222"],"activity_meta":{}}}
    """

    static let leaderboard = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"timeframe":"7d","category":"pnl","rows":[{"profile_id":"22222222-2222-2222-2222-222222222222","pnl":100}],"next_cursor":null}}
    """

    static let calendar = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"year":2026,"month":8,"accounts":[{"id":"33333333-3333-3333-3333-333333333333","name":"Main","type":"live","currency":"USD","is_active":true}],"day_buckets":[{"day":"2026-08-01","pnl":10}],"trades_by_day":{"2026-08-01":[{"id":"t1"}]},"metrics_month":{"net_pnl":10}}}
    """

    static let tradeDetail = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"trade":{"id":"t1","ticker":"ES"},"author":{"id":"22222222-2222-2222-2222-222222222222","username":"trader_a","display_name":"Trader A","avatar_url":null},"engagement":{"like_count":1,"comment_count":0,"liked_by_viewer":true},"comments_page":[],"viewer_state":{"can_edit":true},"next_comments_cursor":null}}
    """

    static let settings = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"profile_settings":{"username":"viewer"},"notification_prefs":{"likes":true},"messaging_prefs":{},"accounts":[{"id":"33333333-3333-3333-3333-333333333333","name":"Main","type":"live","currency":"USD","is_active":true}],"entitlement":{"plan":"pro","status":"active","flags":{"early_access":false}}}}
    """
}
