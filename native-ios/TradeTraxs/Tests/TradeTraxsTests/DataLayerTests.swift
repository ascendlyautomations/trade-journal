import XCTest
@testable import TradeTraxs

final class DataLayerTests: XCTestCase {
    func testDataEnvironmentWiresAllRepositories() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertNotNil(environment.data.trades)
        XCTAssertNotNil(environment.data.profiles)
        XCTAssertNotNil(environment.data.feed)
        XCTAssertNotNil(environment.data.messages)
        XCTAssertNotNil(environment.data.authentication)
        XCTAssertNotNil(environment.data.session)
        XCTAssertEqual(
            environment.data.supabase.client.isConfigured,
            environment.configuration.isSupabaseConfigured
        )
    }

    func testTradeMapperRoundTrip() throws {
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
            points: nil,
            sessionLabel: nil,
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
        XCTAssertEqual(mapped.visibility, .public)
    }

    func testDefaultTradeRepositoryRequiresConfiguration() async {
        let repo = DefaultTradeRepository(
            supabase: .unconfigured,
            session: PlaceholderSessionProvider()
        )
        do {
            _ = try await repo.trades(
                ownedBy: ProfileID("p1"),
                accountID: nil,
                page: PageRequest()
            )
            XCTFail("Expected notConfigured")
        } catch let error as AppError {
            XCTAssertEqual(error, .authentication(.notConfigured))
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testAuthenticationRepositoryHasNoSession() async throws {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        let repo = DefaultAuthenticationRepository(manager: auth.manager)
        let userID = try await repo.currentSessionUserID()
        XCTAssertNil(userID)
    }
}
