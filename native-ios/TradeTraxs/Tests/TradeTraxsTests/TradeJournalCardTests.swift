import XCTest
@testable import TradeTraxs

@MainActor
final class TradeJournalCardTests: XCTestCase {
    func testDurationAndJournalDisplayHelpers() {
        let entry = Date(timeIntervalSince1970: 1_700_000_000)
        let exit = entry.addingTimeInterval(4 * 60 + 32)
        XCTAssertEqual(
            TradeDisplay.durationText(entryAt: entry, exitAt: exit),
            "4m 32s"
        )
        XCTAssertNil(TradeDisplay.durationText(entryAt: entry, exitAt: nil))
        XCTAssertEqual(TradeDisplay.journalRRText(Decimal(string: "2.9")), "1:2.9")
        XCTAssertEqual(TradeDisplay.pointsText(Decimal(string: "21.75")), "+21.75")
        XCTAssertEqual(TradeDisplay.pointsText(Decimal(string: "-3")), "-3")
        XCTAssertEqual(TradeDisplay.contractsText(2), "2")
    }

    func testStrategyMappedFromHistoryDTO() throws {
        let dto = TradeDTO.Trade(
            id: "t1",
            user_id: "u1",
            account_id: nil,
            ticker: "MNQ",
            direction: "Long",
            mode: "live",
            account_type: nil,
            contracts: FlexibleNumber(2),
            entry_price: FlexibleNumber(Decimal(string: "21452.25")),
            exit_price: FlexibleNumber(Decimal(string: "21474")),
            entry_time: "2026-08-11T14:32:00Z",
            exit_time: "2026-08-11T14:36:32Z",
            pnl: FlexibleNumber(437),
            rr: FlexibleNumber(Decimal(string: "2.9")),
            points: FlexibleNumber(Decimal(string: "21.75")),
            session: "NY",
            is_public: false,
            is_pinned: nil,
            public_description: nil,
            image_url: nil,
            notes: "Waited for liquidity sweep and confirmation before entering.",
            created_at: "2026-08-11T14:32:00Z",
            date: nil,
            trade_date: nil,
            account_name: "Alpha 50K",
            strategy: "Opening Range Breakout"
        )
        let trade = try TradeMapper.mapToDomain(dto)
        XCTAssertEqual(trade.strategy, "Opening Range Breakout")
        XCTAssertNil(trade.thumbnail)
        XCTAssertEqual(trade.visibility, .private)
        XCTAssertTrue(trade.notePreview?.contains("liquidity sweep") == true)
        XCTAssertGreaterThan(trade.notePreview?.count ?? 0, 40)
    }

    func testFixtureCardStateCoverage() {
        let trades = ProfileTradeFixtures.samples(owner: ProfileID("dev.journal.cards"))
        let withImageNotes = trades.filter { $0.thumbnail != nil && $0.notePreview != nil }
        let withImageNoNotes = trades.filter { $0.thumbnail != nil && $0.notePreview == nil }
        let noImageNotes = trades.filter { $0.thumbnail == nil && $0.notePreview != nil }
        let noImageNoNotes = trades.filter { $0.thumbnail == nil && $0.notePreview == nil }
        XCTAssertFalse(withImageNotes.isEmpty)
        XCTAssertFalse(withImageNoNotes.isEmpty)
        XCTAssertFalse(noImageNotes.isEmpty)
        XCTAssertFalse(noImageNoNotes.isEmpty)
        XCTAssertTrue(trades.contains { ($0.realizedPnL?.amount ?? 0) > 0 })
        XCTAssertTrue(trades.contains { ($0.realizedPnL?.amount ?? 0) < 0 })
        XCTAssertTrue(trades.contains { $0.visibility == .public })
        XCTAssertTrue(trades.contains { $0.visibility == .private })
        XCTAssertTrue(trades.contains { $0.strategy != nil })
        XCTAssertTrue(trades.contains { $0.points == nil })
    }

    func testHistoryViewModelOpensDetailWithoutEngagementDependency() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = TradeHistoryViewModel(
            trades: TradeJournalCardStubRepository(),
            session: TradeJournalCardStubSession(userID: "dev.journal.vm"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        guard let trade = viewModel.items.first else {
            XCTFail("Expected fixture trades")
            return
        }
        viewModel.openTrade(trade)
        XCTAssertEqual(store.paths.home.last, .tradeDetail(trade.id))
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct TradeJournalCardStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { "token" } }
}

private final class TradeJournalCardStubRepository: TradeRepository, @unchecked Sendable {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        PropFirmFixtures.accounts(owner: profileID)
    }
}
