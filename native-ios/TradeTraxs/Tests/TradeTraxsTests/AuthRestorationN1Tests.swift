import XCTest
@testable import TradeTraxs

final class AuthRestorationN1Tests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        TradeMappingTelemetry.resetForTests()
        let gateClear = Task { await SessionNetworkGate.shared.markUnauthenticated() }
        let flightClear = Task { await AuthRefreshSingleFlight.shared.cancelAll() }
        _ = (gateClear, flightClear)
        super.tearDown()
    }

    func testSafeAuthLogSummaryDoesNotLeakCredentials() {
        let session = AuthenticationSession(
            userID: UserID("11111111-1111-1111-1111-111111111111"),
            email: "secret@example.com",
            accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.secret",
            refreshToken: "refresh-secret-token-value",
            expiresAt: Date().addingTimeInterval(3600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
        let summary = SafeAuthLog.summary(
            for: .authenticated(session),
            session: session,
            expiration: SessionExpiration(leeway: 60),
            correlationID: "test-corr"
        )
        let rendered = """
        \(summary.authState) \(summary.hasAccessToken) \(summary.hasRefreshToken) \
        \(summary.tokenExpiryStatus.rawValue) \(summary.correlationID)
        """
        XCTAssertFalse(SafeAuthLog.containsCredentialLeak(rendered))
        XCTAssertFalse(SafeAuthLog.containsCredentialLeak(String(describing: summary)))
    }

    func testAuthStateDescriptionDoesNotUseSessionPayload() {
        let session = AuthenticationSession(
            userID: UserID("u1"),
            email: "a@b.com",
            accessToken: "access-leak-value",
            refreshToken: "refresh-leak",
            expiresAt: Date().addingTimeInterval(60),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: nil
        )
        let summary = SafeAuthLog.summary(
            for: .refreshing(session),
            session: session,
            expiration: SessionExpiration(leeway: 0),
            correlationID: "c1"
        )
        XCTAssertEqual(summary.authState, "refreshing")
        XCTAssertTrue(summary.hasAccessToken)
        XCTAssertFalse(SafeAuthLog.containsCredentialLeak(summary.authState))
    }

    @MainActor
    func testConcurrentRestoreSharesOneRefresh() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshDelayNanoseconds = 200_000_000
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation, backend: backend)

        let expired = AuthenticationSession(
            userID: UserID("user-1"),
            email: "a@b.com",
            accessToken: "stale",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(-60),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: nil
        )
        try auth.sessionManager.install(expired)
        _ = auth.manager.prepareColdLaunch()

        async let first = auth.manager.restoreSession()
        async let second = auth.manager.restoreSession()
        await first
        await second

        XCTAssertEqual(backend.refreshCallCount, 1)
        XCTAssertTrue(auth.manager.state.isAuthenticated)
    }

    func testFeatureFlagProcessEnvironmentBeatsUserDefaults() {
        BackendV2FeatureFlags.resetFlagsForTests()
        UserDefaults.standard.set(false, forKey: BackendV2FeatureFlag.session.dottedName)
        setenv("BACKEND_V2_SESSION", "1", 1)
        defer {
            unsetenv("BACKEND_V2_SESSION")
            UserDefaults.standard.removeObject(forKey: BackendV2FeatureFlag.session.dottedName)
        }
        let resolved = BackendV2FeatureFlags.resolve(.session)
        XCTAssertTrue(resolved.enabled)
        XCTAssertEqual(resolved.source, "processEnvironment")
    }

    func testFeatureFlagMissingDefaultsOff() {
        BackendV2FeatureFlags.resetFlagsForTests()
        unsetenv("BACKEND_V2_SESSION")
        UserDefaults.standard.removeObject(forKey: BackendV2FeatureFlag.session.dottedName)
        let resolved = BackendV2FeatureFlags.resolve(.session)
        XCTAssertFalse(resolved.enabled)
        XCTAssertEqual(resolved.source, "default")
    }

    func testFeatureFlagZeroEnvironmentOff() {
        BackendV2FeatureFlags.resetFlagsForTests()
        setenv("BACKEND_V2_DASHBOARD", "0", 1)
        defer { unsetenv("BACKEND_V2_DASHBOARD") }
        let resolved = BackendV2FeatureFlags.resolve(.dashboard)
        XCTAssertFalse(resolved.enabled)
        XCTAssertEqual(resolved.source, "processEnvironment")
    }

    func testNullableTickerTradeMapsAndCountsInAnalytics() throws {
        TradeMappingTelemetry.resetForTests()
        let dto = TradeDTO.Trade(
            id: "t-null",
            user_id: "11111111-1111-1111-1111-111111111111",
            account_id: nil,
            ticker: nil,
            direction: "Long",
            mode: nil,
            account_type: nil,
            contracts: nil,
            entry_price: nil,
            exit_price: nil,
            entry_time: "2026-08-01T12:00:00.000Z",
            exit_time: nil,
            pnl: FlexibleNumber(Decimal(250)),
            rr: nil,
            points: nil,
            session: nil,
            is_public: false,
            is_pinned: nil,
            public_description: nil,
            image_url: nil,
            notes: nil,
            created_at: "2026-08-01T12:00:00.000Z",
            date: nil,
            trade_date: nil,
            account_name: nil,
            strategy: nil
        )
        let trade = try TradeMapper.mapToDomain(dto)
        XCTAssertEqual(trade.symbol.ticker, "")
        XCTAssertEqual(trade.realizedPnL?.amount, 250)
        XCTAssertEqual(TradeMappingTelemetry.missingTickerCountForTests(), 1)

        let summary = DashboardChartMetrics.compute(
            from: [DashboardChartMetrics.Input(trade: trade, accountType: nil)],
            accountFilter: .all,
            dateRange: .all,
            payoutTotal: nil
        )
        XCTAssertEqual(summary.tradeCount, 1)
        XCTAssertEqual(summary.netPnL, 250)
    }

    func testDashboardPlaceholderSleepLoopAbsent() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TradeTraxs/Features/Home/Dashboard/ViewModels/DashboardViewModel.swift")
            .path
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(source.contains("Task.sleep(nanoseconds: 60_000_000_000)"))
    }
}
