import XCTest
@testable import TradeTraxs

@MainActor
final class LivePersonalDrawdownPersistenceTests: XCTestCase {
    private let viewerID = ProfileID("11111111-1111-1111-1111-111111111111")
    private let accountID = TradingAccountID("33333333-3333-3333-3333-333333333333")

    override func tearDown() {
        BackendV2BootstrapDiskCache.clearAll()
        DashboardAnalyticsDiskCache.clearAll()
        SessionAccountsStore.shared.invalidate()
        super.tearDown()
    }

  func testDrawdownPatchBodyEncodesNullWhenCleared() throws {
        let body = LivePersonalDrawdownEngine.makeAccountDrawdownPatchBody(config: nil)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["max_drawdown"] is NSNull)
        XCTAssertTrue(json["drawdown_type"] is NSNull)
        XCTAssertTrue(json["drawdown_floor_cap"] is NSNull)
    }

    func testDrawdownPatchBodyEncodesPersistedValues() throws {
        let config = LivePersonalDrawdownConfig(
            limitAmount: 1_500,
            limitType: .trailing,
            floorCap: 50_000
        )
        let body = LivePersonalDrawdownEngine.makeAccountDrawdownPatchBody(config: config)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["max_drawdown"] as? Double, 1_500)
        XCTAssertEqual(json["drawdown_type"] as? String, "end_of_day_trailing")
        XCTAssertEqual(json["drawdown_floor_cap"] as? Double, 50_000)
    }

    func testDrawdownPatchBodyPersistsCapForFixedType() throws {
        let config = LivePersonalDrawdownConfig(
            limitAmount: 1_500,
            limitType: .fixed,
            floorCap: 50_000
        )
        let body = LivePersonalDrawdownEngine.makeAccountDrawdownPatchBody(config: config)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["drawdown_type"] as? String, "static")
        XCTAssertEqual(json["drawdown_floor_cap"] as? Double, 50_000)
    }

    func testLiveDrawdownPatchUpdatesAnalyticsV3DiskCache() throws {
        var bootstrap = AnalyticsDashboardBootstrapV3(
            meta: BootstrapMetaV1(
                contract_version: "v1",
                server_time: "2026-11-22T00:00:00.000Z",
                viewer_id: viewerID.rawValue
            ),
            data: .init(
                revision: nil,
                as_of_et: "2026-11-22",
                payload_kind: "dashboard_analytics_v3_compact",
                payout_total: nil,
                accounts: [
                    DashboardAccountWireV1(
                        id: accountID.rawValue,
                        mode: "Live",
                        category: "Broker",
                        max_drawdown: nil,
                        drawdown_type: nil
                    ),
                ],
                presets: [:],
                account_preset_metrics: [],
                scopes: nil
            )
        )
        DashboardAnalyticsDiskCache.save(
            .init(
                viewerID: viewerID.rawValue,
                contractVersion: "v1",
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: 1,
                savedAt: Date(),
                payload: bootstrap
            )
        )

        let account = TradingAccount(
            id: accountID,
            ownerProfileID: viewerID,
            name: "Live Broker",
            category: .broker,
            mode: .live,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true,
            livePersonalDrawdown: LivePersonalDrawdownStored(
                limitAmount: 3_000,
                limitType: .trailing,
                floorCap: 48_000
            )
        )
        AccountPersistedCacheCoordinator.noteAccountPatched(account, viewerID: viewerID)

        let cached = DashboardAnalyticsDiskCache.load(viewerID: viewerID)
        let row = cached?.payload.data.accounts.first { $0.id == accountID.rawValue }
        XCTAssertEqual(row?.max_drawdown?.value, 3_000)
        XCTAssertEqual(row?.drawdown_type, "end_of_day_trailing")
        XCTAssertEqual(row?.drawdown_floor_cap?.value, 48_000)
    }

    func testLiveDrawdownPatchUpdatesDashboardDiskCache() throws {
        let dashboard: DashboardBootstrapV1 = try JSONDecoder().decode(
            DashboardBootstrapV1.self,
            from: Data(BackendV2ContractFixtures.dashboard.utf8)
        )
        BackendV2BootstrapDiskCache.saveDashboard(dashboard, viewerID: viewerID.rawValue)

        var account = TradingAccount(
            id: accountID,
            ownerProfileID: viewerID,
            name: "Live",
            category: .broker,
            mode: .live,
            size: Money(amount: 25_000),
            isActive: true,
            canAddTrades: true,
            livePersonalDrawdown: LivePersonalDrawdownStored(
                limitAmount: 2_500,
                limitType: .trailing
            )
        )
        AccountPersistedCacheCoordinator.noteAccountPatched(account, viewerID: viewerID)

        let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: viewerID.rawValue)
        let row = cached?.bootstrap.data.accounts.first { $0.id == accountID.rawValue }
        XCTAssertEqual(row?.max_drawdown?.value, 2_500)
        XCTAssertEqual(row?.drawdown_type, "end_of_day_trailing")
    }

    func testRestBootstrapMergeKeepsConfiguredLiveDrawdown() {
        let configured = TradingAccount(
            id: accountID,
            ownerProfileID: viewerID,
            name: "Live",
            category: .personal,
            mode: .live,
            size: Money(amount: 10_000),
            isActive: true,
            canAddTrades: true,
            livePersonalDrawdown: LivePersonalDrawdownStored(limitAmount: 900, limitType: .fixed)
        )
        SessionAccountsStore.shared.seed([configured], for: viewerID, kind: .rest)

        var stale = configured
        stale.livePersonalDrawdown = nil
        SessionAccountsStore.shared.seed([stale], for: viewerID, kind: .rest)

        let cached = SessionAccountsStore.shared.cached(for: viewerID)?.first { $0.id == accountID }
        XCTAssertEqual(cached?.livePersonalDrawdown?.limitAmount, 900)
        XCTAssertEqual(cached?.livePersonalDrawdown?.limitType, .fixed)
    }
}