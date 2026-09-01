import XCTest
@testable import TradeTraxs

final class DashboardBootstrapDecoderN21Tests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2BootstrapDiskCache.clearAll()
        DashboardLoadProbe.resetForTesting()
        TradeMappingTelemetry.resetForTests()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        super.tearDown()
    }

    func testProductionShapeFixtureDecodes() throws {
        let value: DashboardBootstrapV1 = try decode(DashboardBootstrapDecoderFixtures.productionShape)
        XCTAssertEqual(value.data.accounts.first?.account_size?.raw, "50000")
        XCTAssertEqual(value.data.trade_window.count, 2)
        XCTAssertNil(value.data.trade_window.first?.ticker)
        XCTAssertEqual(value.data.trade_window_meta.returned, 2)
        XCTAssertEqual(value.data.metrics.total_trades?.value, 2)
    }

    func testStringAccountSizeDoesNotFailDecode() throws {
        let json = """
        {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":"a","account_size":"50000"}],"trade_window":[],"trade_window_meta":{"limit":500,"returned":0,"history_complete":true,"total_trade_count":0,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
        """
        XCTAssertNoThrow(try decode(json))
    }

    func testLegacyDoubleAccountSizeStillDecodes() throws {
        let json = """
        {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":"a","account_size":50000}],"trade_window":[],"trade_window_meta":{"limit":500,"returned":0,"history_complete":true,"total_trade_count":0,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
        """
        let value = try decode(json)
        XCTAssertEqual(value.data.accounts.first?.account_size?.raw, "50000")
    }

    func testNullOptionalTradeFieldsDecode() throws {
        let value: DashboardBootstrapV1 = try decode(DashboardBootstrapDecoderFixtures.nullOptionalTrade)
        XCTAssertEqual(value.data.trade_window.count, 1)
        XCTAssertNil(value.data.trade_window[0].ticker)
        XCTAssertNil(value.data.trade_window[0].notes)
        XCTAssertNil(value.data.trade_window[0].image_url)
    }

    func testUnknownAdditiveFieldIgnored() throws {
        let json = DashboardBootstrapDecoderFixtures.productionShape.replacingOccurrences(
            of: "\"recent_trades\"",
            with: "\"future_section\":{\"enabled\":true},\"recent_trades\""
        )
        XCTAssertNoThrow(try decode(json))
    }

    func testMissingRequiredMetaFails() {
        let json = """
        {"data":{"accounts":[],"trade_window":[],"trade_window_meta":{"limit":500,"returned":0,"history_complete":true,"total_trade_count":0,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testWrongAccountIdTypeFails() {
        let json = """
        {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":123}],"trade_window":[],"trade_window_meta":{"limit":500,"returned":0,"history_complete":true,"total_trade_count":0,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testDecodingDiagnosticsSnapshot() {
        let json = """
        {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":"a","account_size":[]}],"trade_window":[],"trade_window_meta":{"limit":500,"returned":0,"history_complete":true,"total_trade_count":0,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
        """
        do {
            _ = try decode(json)
            XCTFail("Expected decode failure")
        } catch let error as DecodingError {
            let snap = BackendV2DecodingDiagnostics.snapshot(from: error)
            XCTAssertEqual(snap?.category, "typeMismatch")
            XCTAssertTrue(snap?.codingPath.contains("account_size") == true)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    @MainActor
    func testValidPayloadMapsToDashboardState() async throws {
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let detailCache = DetailPresentationCache()
        let rpc = DashboardFixtureRPCClient(json: DashboardBootstrapDecoderFixtures.productionShape)

        let result = try await DashboardBootstrapLoader.load(
            viewerID: viewer,
            rpc: rpc,
            detailCache: detailCache,
            forceNetwork: true,
            loadGeneration: 1,
            currentGeneration: { 1 }
        )

        XCTAssertEqual(result.path, .v2_rpc)
        XCTAssertFalse(result.applied.trades.isEmpty)
        XCTAssertFalse(result.applied.accounts.isEmpty)
    }

    @MainActor
    func testMalformedOptionalTradeRowSkippedNotEmptySuccess() async throws {
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let viewer = ProfileID("11111111-1111-1111-1111-111111111111")
        let bootstrap: DashboardBootstrapV1 = try decode(DashboardBootstrapDecoderFixtures.oneInvalidTradeRow)
        let applied = try await DashboardBootstrapApplier.apply(
            bootstrap,
            expectedViewerID: viewer.rawValue,
            detailCache: DetailPresentationCache()
        )
        XCTAssertEqual(applied.trades.count, 1)
        XCTAssertEqual(applied.skippedTrades, 1)
    }

    @MainActor
    func testDecodeFailureColdLoadDoesNotRetryRPC() async {
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let rpc = DashboardMalformedRPCClient()
        let viewModel = DashboardViewModel(
            home: DecoderN21HomeRepository(),
            trades: DecoderN21TradeRepository(),
            achievements: DecoderN21AchievementRepository(),
            session: DecoderN21Session(userID: "11111111-1111-1111-1111-111111111111"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: rpc
        )
        await SessionNetworkGate.shared.markReady()
        viewModel.loadIfNeeded()
        await waitFor(timeout: 3) { viewModel.phase != .loading }
        viewModel.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(rpc.callCount, 1)
        if case .failed = viewModel.phase {
            // expected
        } else {
            XCTFail("Expected failed phase, got \(viewModel.phase)")
        }
    }

    @MainActor
    func testExplicitRefreshIssuesOneNewRPC() async {
        BackendV2FeatureFlags.setFlagForTests(.dashboard, enabled: true)
        let rpc = DashboardFixtureRPCClient(json: DashboardBootstrapDecoderFixtures.productionShape)
        let viewModel = DashboardViewModel(
            home: DecoderN21HomeRepository(),
            trades: DecoderN21TradeRepository(),
            achievements: DecoderN21AchievementRepository(),
            session: DecoderN21Session(userID: "11111111-1111-1111-1111-111111111111"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            rpc: rpc
        )
        await SessionNetworkGate.shared.markReady()
        viewModel.loadIfNeeded()
        await waitFor(timeout: 3) { viewModel.phase == .loaded }
        await viewModel.refresh()
        XCTAssertEqual(rpc.callCount, 2)
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func decode(_ json: String) throws -> DashboardBootstrapV1 {
        try JSONDecoder().decode(DashboardBootstrapV1.self, from: Data(json.utf8))
    }
}

enum DashboardBootstrapDecoderFixtures {
    /// Sanitized shape aligned with deployed `rpc_v1_dashboard_bootstrap` (string account_size, nullable ticker).
    static let productionShape = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-19T20:00:00.000Z","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":"33333333-3333-3333-3333-333333333333","account_number":"1","name":"Main","account_size":"50000","mode":"Funded","category":"Prop Firm","is_active":true,"can_add_trades":true,"note":null,"consistency":"0.5","max_drawdown":null,"daily_drawdown":null,"profit_target":null,"winning_days":null,"winning_day_threshold":null}],"trade_window":[{"id":"trade-2","user_id":"11111111-1111-1111-1111-111111111111","ticker":null,"direction":"Long","entry_time":"2026-08-02T12:00:00.000Z","created_at":"2026-08-02T12:00:00.000Z","pnl":-50,"mode":"live","account_id":"33333333-3333-3333-3333-333333333333","notes":null,"image_url":null,"copied_account_ids":[]},{"id":"trade-1","user_id":"11111111-1111-1111-1111-111111111111","ticker":"NQ","direction":"Short","entry_time":"2026-08-01T12:00:00.000Z","created_at":"2026-08-01T12:00:00.000Z","pnl":100,"mode":"Eval","account_id":"33333333-3333-3333-3333-333333333333","notes":"private","image_url":null,"copied_account_ids":[]}],"trade_window_meta":{"limit":500,"returned":2,"history_complete":false,"total_trade_count":120,"oldest_created_at":"2026-01-01T00:00:00.000Z","next_cursor":null},"metrics":{"total_trades":2,"wins":1,"losses":1,"win_rate":0.5,"net_pnl":50,"avg_rr":1.25,"avg_win":100,"avg_loss":-50,"biggest_win":100,"biggest_loss":-50},"equity_points":[{"t":"2026-08-01T12:00:00.000Z","v":100},{"t":"2026-08-02T12:00:00.000Z","v":50}],"payout_total":"1250.50","recent_trades":[{"id":"trade-2"},{"id":"trade-1"}]}}
    """

    static let nullOptionalTrade = """
    {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[],"trade_window":[{"id":"t1","user_id":"11111111-1111-1111-1111-111111111111","ticker":null,"direction":null,"entry_time":"2026-08-01T12:00:00.000Z","created_at":"2026-08-01T12:00:00.000Z","pnl":null,"notes":null,"image_url":null,"exit_time":null,"account_id":null}],"trade_window_meta":{"limit":500,"returned":1,"history_complete":true,"total_trade_count":1,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":null,"recent_trades":[{"id":"t1"}]}}
    """

    static let oneInvalidTradeRow = """
    {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[],"trade_window":[{"id":"good","user_id":"11111111-1111-1111-1111-111111111111","entry_time":"2026-08-01T12:00:00.000Z","created_at":"2026-08-01T12:00:00.000Z","pnl":10},{"id":"bad","user_id":"11111111-1111-1111-1111-111111111111"}],"trade_window_meta":{"limit":500,"returned":2,"history_complete":true,"total_trade_count":2,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
    """

    static let invalidAccountSize = """
    {"meta":{"contract_version":"v1","server_time":"t","viewer_id":"11111111-1111-1111-1111-111111111111"},"data":{"accounts":[{"id":"a","account_size":[]}],"trade_window":[],"trade_window_meta":{"limit":500,"returned":0,"history_complete":true,"total_trade_count":0,"oldest_created_at":null,"next_cursor":null},"metrics":{},"equity_points":[],"payout_total":0,"recent_trades":[]}}
    """
}

private final class DashboardFixtureRPCClient: RPCClient, @unchecked Sendable {
    let json: String
    private(set) var callCount = 0
    init(json: String) { self.json = json }
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }
    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        return Data(json.utf8)
    }
}

private final class DashboardMalformedRPCClient: RPCClient, @unchecked Sendable {
    private(set) var callCount = 0
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        return Data(DashboardBootstrapDecoderFixtures.invalidAccountSize.utf8)
    }
    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        return Data(DashboardBootstrapDecoderFixtures.invalidAccountSize.utf8)
    }
}

private struct DecoderN21Session: SessionProviding {
    let userID: String
    var currentUserID: UserID? { get async { UserID(userID) } }
    var accessToken: String? { get async { "token" } }
}

private struct DecoderN21HomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        throw AppError.notImplemented(feature: "home")
    }
    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        throw AppError.notImplemented(feature: "performance")
    }
}

private struct DecoderN21TradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.notImplemented(feature: "trade") }
    func trades(ownedBy profileID: ProfileID, accountID: TradingAccountID?, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ draft: TradeDraft) async throws -> Trade { throw AppError.notImplemented(feature: "save") }
    func update(_ trade: Trade) async throws -> Trade { throw AppError.notImplemented(feature: "update") }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        throw AppError.notImplemented(feature: "statistics")
    }
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
}

private struct DecoderN21AchievementRepository: AchievementRepository {
    func achievements(for profileID: ProfileID, page: PageRequest, publicOnly: Bool) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.notImplemented(feature: "achievement")
    }

    func save(_ achievement: Achievement) async throws -> Achievement { achievement }
}
