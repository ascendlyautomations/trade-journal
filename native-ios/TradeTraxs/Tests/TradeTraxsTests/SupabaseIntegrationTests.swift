import XCTest
@testable import TradeTraxs

final class SupabaseIntegrationTests: XCTestCase {
    func testBootstrapWiresSupabaseInfrastructure() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertNotNil(environment.data.supabase.database)
        XCTAssertNotNil(environment.data.rpc)
        XCTAssertNotNil(environment.data.edgeFunctions)
        XCTAssertNotNil(environment.data.uploadService)
        XCTAssertNotNil(environment.data.session)
        XCTAssertEqual(
            environment.configuration.isSupabaseConfigured,
            environment.data.supabase.client.isConfigured
        )
    }

    func testRepositoryDependencyInjection() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertTrue(environment.data.trades is DefaultTradeRepository)
        XCTAssertTrue(environment.data.profiles is DefaultProfileRepository)
        XCTAssertTrue(environment.data.feed is DefaultFeedRepository)
        XCTAssertTrue(environment.data.home is DefaultHomeRepository)
        XCTAssertTrue(environment.data.authentication is DefaultAuthenticationRepository)
    }

    func testDTOMappingTradeRoundTrip() throws {
        let trade = Trade(
            id: TradeID("t1"),
            ownerProfileID: ProfileID("p1"),
            accountID: TradingAccountID("a1"),
            symbol: Symbol(ticker: "NQ"),
            side: .short,
            mode: .live,
            quantity: 2,
            entryPrice: 18000,
            exitPrice: 17950,
            entryAt: Date(timeIntervalSince1970: 1_700_000_000),
            exitAt: Date(timeIntervalSince1970: 1_700_000_100),
            realizedPnL: Money(amount: 250, currencyCode: "USD"),
            riskReward: Decimal(string: "2.5"),
            points: 10,
            sessionLabel: "NY",
            visibility: .public,
            publicCaption: "fade",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let dto = try TradeMapper.mapToDTO(trade)
        let mapped = try TradeMapper.mapToDomain(dto)
        XCTAssertEqual(mapped.id, trade.id)
        XCTAssertEqual(mapped.symbol.ticker, "NQ")
        XCTAssertEqual(mapped.side, .short)
        XCTAssertEqual(mapped.ownerProfileID, trade.ownerProfileID)
    }

    func testRealtimeBootstrapLifecycle() async {
        let realtime = DisconnectedTestRealtime()
        let hub = RealtimeHub(realtime: realtime)
        XCTAssertFalse(hub.isActive)
        hub.start()
        XCTAssertTrue(hub.isActive)
        await hub.stop()
        XCTAssertFalse(hub.isActive)
        XCTAssertTrue(realtime.disconnectCalled)
    }

    func testStorageBootstrapPublicURL() {
        let configuration = AppConfiguration(
            buildConfiguration: .debug,
            apiBaseURL: nil,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon",
            appDisplayName: "TradeTraxs"
        )
        let environment = CompositionRoot.bootstrap()
        let storage = LiveSupabaseStorageProvider(
            transport: SupabaseTransport(
                client: environment.networking.client,
                requestBuilder: environment.networking.requestBuilder,
                configuration: configuration
            )
        )
        let url = storage.publicURL(bucket: StorageBucket.screenshots.rawValue, path: "u1/a.png")
        XCTAssertEqual(
            url?.absoluteString,
            "https://example.supabase.co/storage/v1/object/public/screenshots/u1/a.png"
        )
    }

    func testRPCAndEdgeClientsAreWired() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertTrue(environment.data.rpc is DefaultRPCClient)
        XCTAssertTrue(environment.data.edgeFunctions is DefaultEdgeFunctionClient)
    }

    func testSessionRestorationUsesAuthenticationManager() {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        let state = auth.manager.prepareColdLaunch()
        XCTAssertEqual(state, .unauthenticated)
    }

    func testTokenRefreshCoordinatorExistsOnManager() async throws {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        let session = try await auth.emailProvider.signIn(email: "a@b.com", password: "password1")
        try auth.sessionManager.install(session)
        XCTAssertEqual(auth.sessionManager.accessToken, session.accessToken)
        await auth.manager.logout()
        XCTAssertNil(auth.sessionManager.accessToken)
    }

    func testUnconfiguredDatabaseThrowsMappedError() async {
        let db = UnconfiguredSupabaseDatabaseClient()
        do {
            let _: [TradeDTO.Trade] = try await db.select(TradeDTO.Trade.self, from: "trades")
            XCTFail("Expected notConfigured")
        } catch let error as AppError {
            XCTAssertEqual(error, .authentication(.notConfigured))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

private final class DisconnectedTestRealtime: SupabaseRealtimeProviding, @unchecked Sendable {
    private(set) var disconnectCalled = false
    var isConnected: Bool { false }
    func connect() async throws {}
    func disconnect() async { disconnectCalled = true }
}
