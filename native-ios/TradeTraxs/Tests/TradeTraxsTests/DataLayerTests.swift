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

    func testISO8601ParsesPostgresTimestamps() {
        XCTAssertNotNil(ISO8601.date(from: "2024-06-01T15:30:00.123Z"))
        XCTAssertNotNil(ISO8601.date(from: "2024-06-01T15:30:00Z"))
        XCTAssertNotNil(ISO8601.date(from: "2024-06-01 15:30:00+00"))
        XCTAssertNotNil(ISO8601.date(from: "2024-06-01 15:30:00.123456+00"))
        XCTAssertNotNil(ISO8601.date(from: "2024-06-01"))
        XCTAssertNil(ISO8601.date(from: ""))
        XCTAssertNil(ISO8601.date(from: nil))
    }

    func testTradeMapperSkipsOnlyWhenTrulyInvalid() {
        var bad = TradeDTO.Trade(
            id: "t1",
            user_id: "p1",
            account_id: nil,
            ticker: nil,
            direction: "Long",
            mode: "live",
            account_type: nil,
            contracts: nil,
            entry_price: nil,
            exit_price: nil,
            entry_time: "2024-06-01 15:30:00+00",
            exit_time: nil,
            pnl: FlexibleNumber(10),
            rr: nil,
            points: nil,
            session: nil,
            is_public: true,
            is_pinned: nil,
            public_description: nil,
            image_url: nil,
            notes: nil,
            created_at: "2024-06-01 15:30:00+00",
            date: nil,
            trade_date: nil
        )
        XCTAssertThrowsError(try TradeMapper.mapToDomain(bad))

        bad.ticker = "NQ"
        XCTAssertNoThrow(try TradeMapper.mapToDomain(bad))
    }

    func testProfileOverviewMetricsMatchWebFormulas() {
        let rows: [ProfileOverviewMetrics.TradeInput] = [
            .init(pnl: 100, rr: 2, mode: "live", accountType: nil),
            .init(pnl: -50, rr: 1, mode: "live", accountType: nil),
            .init(pnl: 25, rr: nil, mode: "backtest", accountType: nil),
            .init(pnl: 10, rr: 3, mode: "live", accountType: "backtest"),
        ]
        let result = ProfileOverviewMetrics.compute(from: rows)
        // Backtest excluded → 2 trades, 1 win → 50%
        XCTAssertEqual(result.publicTradeCount, 2)
        XCTAssertEqual(result.winRate, Decimal(string: "0.5"))
        XCTAssertEqual(result.netPnL, 50)
        XCTAssertEqual(result.averageRR, Decimal(string: "1.5"))
        // PF = 100 / 50 = 2
        XCTAssertEqual(result.profitFactor, 2)
        XCTAssertNil(result.expectancy)
    }

    func testAchievementKindMatchesWebAchievementTypeStrings() {
        XCTAssertEqual(AchievementKind(rawValue: "prop_firm_payout"), .propFirmPayout)
        XCTAssertEqual(AchievementKind(rawValue: "live_trading_payout"), .liveTradingPayout)
        XCTAssertEqual(AchievementKind(rawValue: "passed_eval"), .passedEvaluation)
        XCTAssertEqual(AchievementKind(rawValue: "milestone"), .milestone)
        XCTAssertEqual(AchievementDTO.ownerSelect.contains("achievement_type"), true)
        XCTAssertEqual(AchievementDTO.publicSelect.contains("account_name"), false)
        XCTAssertEqual(AchievementDTO.ownerSelect.contains("account_name"), true)
    }

    func testAchievementDTODecodesWebSelectShape() throws {
        let json = """
        {
          "id": "a1",
          "user_id": "p1",
          "achievement_type": "live_trading_payout",
          "title": "Payout",
          "description": null,
          "badge_key": null,
          "tier": "silver",
          "category": "live_trading_payouts",
          "value_numeric": 500,
          "value_text": null,
          "currency": "USD",
          "account_type": null,
          "mode": "live",
          "firm": null,
          "image_url": null,
          "achieved_at": "2024-06-01T12:00:00Z",
          "created_at": "2024-06-01T12:00:00Z",
          "updated_at": "2024-06-01T12:00:00Z",
          "is_featured": false,
          "is_public": true,
          "sort_order": 0,
          "metadata": {"source": "test"}
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(AchievementDTO.Achievement.self, from: json)
        XCTAssertEqual(dto.id, "a1")
        XCTAssertEqual(dto.achievement_type, "live_trading_payout")
        XCTAssertEqual(dto.is_public, true)
        XCTAssertNotNil(dto.metadata)
    }

    func testProfileOverviewMetricsProfitFactorNilWithoutLosses() {
        let rows: [ProfileOverviewMetrics.TradeInput] = [
            .init(pnl: 100, rr: 2, mode: "live", accountType: nil),
            .init(pnl: 50, rr: 1, mode: "funded", accountType: nil),
        ]
        let result = ProfileOverviewMetrics.compute(from: rows)
        XCTAssertEqual(result.publicTradeCount, 2)
        XCTAssertEqual(result.winRate, 1)
        XCTAssertNil(result.profitFactor)
    }

    func testProfileStatisticsMetricsMatchWebFormulas() {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let rows: [ProfileStatisticsMetrics.TradeInput] = [
            .init(pnl: 100, createdAt: base.addingTimeInterval(3 * day), isLong: true, session: "NY", mode: "live", accountType: "eval"),
            .init(pnl: -40, createdAt: base.addingTimeInterval(2 * day), isLong: false, session: "London", mode: "live", accountType: "eval"),
            .init(pnl: 60, createdAt: base.addingTimeInterval(1 * day), isLong: true, session: "Asia Session", mode: "live", accountType: "funded"),
            .init(pnl: 25, createdAt: base, isLong: true, session: "NY", mode: "backtest", accountType: nil),
        ]

        let all = ProfileStatisticsMetrics.compute(from: rows, selectedMode: .all)
        // Backtest excluded → 3 trades
        XCTAssertEqual(all.filteredTradeCount, 3)
        // Wins 2 / 3
        XCTAssertEqual(all.winRate, Decimal(2) / Decimal(3))
        // PF = 160 / 40 = 4
        XCTAssertEqual(all.profitFactor, 4)
        // Avg winner = 160 / 2 = 80
        XCTAssertEqual(all.averageWinner, 80)
        // Avg loser = -40 / 1
        XCTAssertEqual(all.averageLoser, -40)
        // Profit/trade = 120 / 3 = 40
        XCTAssertEqual(all.profitPerTrade, 40)
        XCTAssertEqual(all.biggestWin, 100)
        XCTAssertEqual(all.biggestLoss, -40)
        XCTAssertEqual(all.longTrades, 2)
        // Chronological: +60, -40, +100 → max W1 / L1
        XCTAssertEqual(all.maxWinStreak, 1)
        XCTAssertEqual(all.maxLossStreak, 1)
        XCTAssertEqual(all.sessionTotal, 3)
        XCTAssertEqual(all.sessionBreakdown.map(\.label), ["NY", "London", "Asia"])
        XCTAssertEqual(all.currentEquity, 120)
        XCTAssertEqual(all.equityData.count, 3)

        let eval = ProfileStatisticsMetrics.compute(from: rows, selectedMode: .eval)
        XCTAssertEqual(eval.filteredTradeCount, 2)
        XCTAssertEqual(eval.currentEquity, 60)

        let funded = ProfileStatisticsMetrics.compute(from: rows, selectedMode: .funded)
        XCTAssertEqual(funded.filteredTradeCount, 1)
        XCTAssertEqual(funded.longTrades, 1)
    }

    func testProfileStatisticsModeAcceptsEvaluationAlias() {
        let rows: [ProfileStatisticsMetrics.TradeInput] = [
            .init(pnl: 10, createdAt: Date(), isLong: true, session: nil, mode: "live", accountType: "evaluation"),
        ]
        let result = ProfileStatisticsMetrics.compute(from: rows, selectedMode: .eval)
        XCTAssertEqual(result.filteredTradeCount, 1)
    }

    func testTradingAccountMapperPrefersAccountsNameColumn() throws {
        let dto = TradeDTO.Account(
            id: "a1",
            user_id: "p1",
            name: "Apex 50K",
            account_name: "Ignored Registry",
            account_type: "personal",
            category: nil,
            mode: "live",
            account_size: FlexibleNumber(Decimal(50_000)),
            size: nil,
            is_active: true,
            can_add_trades: true
        )
        let account = try TradingAccountMapper.mapToDomain(dto)
        XCTAssertEqual(account.id, TradingAccountID("a1"))
        XCTAssertEqual(account.name, "Apex 50K")
        XCTAssertEqual(account.category, .personal)
        XCTAssertEqual(account.size?.amount, Decimal(50_000))
    }

    func testTradingAccountMapperFallsBackToAccountName() throws {
        let dto = TradeDTO.Account(
            id: "a1",
            user_id: "p1",
            name: nil,
            account_name: "Legacy",
            account_type: "personal",
            category: nil,
            mode: "live",
            account_size: nil,
            size: nil,
            is_active: true,
            can_add_trades: true
        )
        let account = try TradingAccountMapper.mapToDomain(dto)
        XCTAssertEqual(account.name, "Legacy")
    }

    func testTradingAccountMapperMissingNameThrows() {
        let dto = TradeDTO.Account(
            id: "a1",
            user_id: "p1",
            name: nil,
            account_name: nil,
            account_type: nil,
            category: nil,
            mode: nil,
            account_size: nil,
            size: nil,
            is_active: nil,
            can_add_trades: nil
        )
        XCTAssertThrowsError(try TradingAccountMapper.mapToDomain(dto)) { error in
            XCTAssertEqual(error as? MappingError, .missingField("name"))
        }
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
            thumbnail: nil,
            notePreview: nil,
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
                page: PageRequest(),
                publicOnly: true
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
