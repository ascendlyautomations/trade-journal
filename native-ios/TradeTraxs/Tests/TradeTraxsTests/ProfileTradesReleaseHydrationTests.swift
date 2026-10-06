import XCTest
@testable import TradeTraxs

/// Release-shaped sequence: bootstrap preview → V2 journal → bootstrap must not regress copy summary.
@MainActor
final class ProfileTradesReleaseHydrationTests: XCTestCase {
    private let profileID = ProfileID("e432738b-47bd-439b-a669-c71082202895")
    private let sourceID = TradingAccountID("0693ad68-984a-4c87-b14e-125e5bab78a7")
    private let copyB = TradingAccountID("977fda74-dd2d-42f8-8947-818797f31378")
    private let copyC = TradingAccountID("27d939a6-2673-4c9d-96ac-1166838dfa60")

    func testEndOfTradesClearsStaleLoadMoreError() async {
        let environment = CompositionRoot.bootstrapAppEnvironment()
        let viewModel = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            session: environment.data.session,
            rpc: environment.data.rpc,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache,
            tradeDetailRepository: environment.data.tradeDetailRepository
        )
        viewModel.testing_setLoadedPagination(
            nextCursor: nil,
            paginationError: "Please try again."
        )

        await viewModel.loadMoreIfNeeded(currentTradeID: nil)

        XCTAssertNil(viewModel.paginationErrorMessage)
        XCTAssertNil(viewModel.nextCursor)
    }

    func testLoadMoreErrorStaysWhileAnotherPageRemains() async {
        let environment = CompositionRoot.bootstrapAppEnvironment()
        let viewModel = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            session: environment.data.session,
            rpc: environment.data.rpc,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache,
            tradeDetailRepository: environment.data.tradeDetailRepository
        )
        viewModel.testing_setLoadedPagination(
            nextCursor: "2026-10-05T00:00:00.000Z|00000000-0000-0000-0000-000000000001",
            paginationError: "Please try again."
        )

        await viewModel.loadMoreIfNeeded(currentTradeID: nil)

        XCTAssertEqual(viewModel.paginationErrorMessage, "Please try again.")
        XCTAssertNotNil(viewModel.nextCursor)
    }

    func testProfileTradesSummaryV2IsProductionShipped() {
        XCTAssertTrue(BackendV2FeatureFlags.productionShippedFlags.contains(.profileTradesSummaryV2))
    }

    func testSufficientBootstrapPreviewDoesNotRefetchTheFirstPage() {
        BackendV2FeatureFlags.setFlagForTests(.profile, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: true)
        defer {
            BackendV2FeatureFlags.setFlagForTests(.profile, enabled: nil)
            BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: nil)
        }

        let viewModel = makeViewModel()
        var bootstrap = ProfileState()
        bootstrap.phase = .loaded
        bootstrap.didBootstrap = true
        bootstrap.didLoadTrades = true
        bootstrap.tradeJournalPreview = v2JournalRows()
        bootstrap.trades = bootstrap.tradeJournalPreview.map(\.summary)
        bootstrap.tradesNextCursor = "2026-10-05T04:11:26.139000Z|5c0ecd0e-9936-4b2f-aa4f-536ff4dac24a"
        bootstrap.accountModes = publicAccountModes()
        viewModel.applyBootstrap(bootstrap)
        viewModel.hydrateAuthoritativeJournalIfNeeded()

        XCTAssertFalse(viewModel.isHydratingAuthoritativeJournal)
        XCTAssertEqual(viewModel.nextCursor, bootstrap.tradesNextCursor)
        XCTAssertEqual(viewModel.visibleItems.count, 1)
        XCTAssertEqual(
            viewModel.visibleItems[0].copyTradePublicModeSummary,
            "Copy Traded across 3 accounts • 2 Funded • 1 Eval"
        )
    }

    func testSummaryOnlyCopyBootstrapStillRequestsAuthoritativeJournal() {
        BackendV2FeatureFlags.setFlagForTests(.profile, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: true)
        defer {
            BackendV2FeatureFlags.setFlagForTests(.profile, enabled: nil)
            BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: nil)
        }

        let viewModel = makeViewModel()
        var bootstrap = ProfileState()
        bootstrap.phase = .loaded
        bootstrap.didBootstrap = true
        bootstrap.didLoadTrades = true
        bootstrap.trades = reducedBootstrapSummaries()
        bootstrap.tradesNextCursor = "2026-10-05T04:11:26.139000Z|5c0ecd0e-9936-4b2f-aa4f-536ff4dac24a"
        bootstrap.accountModes = publicAccountModes()
        viewModel.applyBootstrap(bootstrap)

        XCTAssertTrue(viewModel.isHydratingAuthoritativeJournal)
        XCTAssertEqual(viewModel.nextCursor, bootstrap.tradesNextCursor)
    }

    func testEmptyBootstrapPageDoesNotRequestAnotherTradePage() {
        BackendV2FeatureFlags.setFlagForTests(.profile, enabled: true)
        BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: true)
        defer {
            BackendV2FeatureFlags.setFlagForTests(.profile, enabled: nil)
            BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: nil)
        }

        let viewModel = makeViewModel()
        var bootstrap = ProfileState()
        bootstrap.phase = .loaded
        bootstrap.didBootstrap = true
        bootstrap.didLoadTrades = true
        viewModel.applyBootstrap(bootstrap)
        viewModel.hydrateAuthoritativeJournalIfNeeded()

        XCTAssertFalse(viewModel.isHydratingAuthoritativeJournal)
        XCTAssertNil(viewModel.nextCursor)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testBootstrapThenV2ThenBootstrapReconcileKeepsFullCopySummary() {
        BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: true)
        defer { BackendV2FeatureFlags.setFlagForTests(.profileTradesSummaryV2, enabled: nil) }

        let environment = CompositionRoot.bootstrapAppEnvironment()
        let viewModel = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            session: environment.data.session,
            rpc: environment.data.rpc,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache,
            tradeDetailRepository: environment.data.tradeDetailRepository
        )

        var bootstrap = ProfileState()
        bootstrap.phase = .loaded
        bootstrap.didBootstrap = true
        bootstrap.didLoadTrades = true
        bootstrap.trades = reducedBootstrapSummaries()
        bootstrap.accountModes = publicAccountModes()
        viewModel.applyBootstrap(bootstrap)

        viewModel.installAuthoritativeV2JournalForTests(v2JournalRows())

        var republish = bootstrap
        republish.trades = reducedBootstrapSummaries()
        viewModel.applyBootstrap(republish)

        let visible = viewModel.visibleItems
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(
            visible[0].copyTradePublicModeSummary,
            "Copy Traded across 3 accounts • 2 Funded • 1 Eval"
        )
    }

    func testParticipatingIDsResolveModesFromPublicAccountModesWhenSiblingAccountIDMissing() {
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "group"
        )
        let thinRows = [
            journalRow(id: "a", account: nil, mode: nil, metadata: metadata),
            journalRow(id: "b", account: nil, mode: nil, metadata: metadata),
            journalRow(id: "c", account: nil, mode: nil, metadata: metadata),
        ]
        let visible = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: thinRows,
            filter: .all,
            sort: .newest,
            accountModesByID: publicAccountModes()
        )
        XCTAssertEqual(
            visible[0].copyTradePublicModeSummary,
            "Copy Traded across 3 accounts • 2 Funded • 1 Eval"
        )
    }

    private func makeViewModel() -> TradesContainerViewModel {
        let environment = CompositionRoot.bootstrapAppEnvironment()
        return TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            session: environment.data.session,
            rpc: environment.data.rpc,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache,
            tradeDetailRepository: environment.data.tradeDetailRepository
        )
    }

    private func publicAccountModes() -> [TradingAccountID: TradingAccountMode] {
        [
            sourceID: .evaluation,
            copyB: .funded,
            copyC: .funded,
        ]
    }

    private func reducedBootstrapSummaries() -> [TradeSummary] {
        v2JournalRows().map(\.summary)
    }

    private func v2JournalRows() -> [TradeOwnerJournalSummary] {
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "044dd34a-f234-42b2-a18f-bf50fa6f5071"
        )
        return [
            journalRow(id: "d6aa7038-cea7-4625-9e52-bc8cb2e55997", account: sourceID, mode: .evaluation, metadata: metadata),
            journalRow(id: "b6afceb2-46da-43f4-90ea-00e54b9b2fb0", account: copyB, mode: .funded, metadata: metadata),
            journalRow(id: "5c0ecd0e-9936-4b2f-aa4f-536ff4dac24a", account: copyC, mode: .funded, metadata: metadata),
        ]
    }

    private func journalRow(
        id: String,
        account: TradingAccountID?,
        mode: TradingAccountMode?,
        metadata: CopyTradeJournalMetadata
    ) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: TradeSummary(
                id: TradeID(id),
                ownerProfileID: profileID,
                symbol: Symbol(ticker: "MNQ"),
                side: .long,
                realizedPnL: Money(amount: 60, currencyCode: "USD"),
                riskReward: 3,
                points: 5,
                quantity: 1,
                entryAt: ISO8601.date(from: "2026-10-05T04:07:00.000Z")!,
                exitAt: nil,
                createdAt: ISO8601.date(from: "2026-10-05T04:11:26.139Z")!,
                visibility: .public,
                publicCaption: "IFVG",
                notePreview: nil,
                thumbnail: nil,
                imageDisplayMode: .fit,
                mode: .copyTraded,
                accountMode: mode,
                publicAccountBadge: nil,
                durationSeconds: 192,
                durationText: "3m 12s"
            ),
            accountID: account,
            accountName: nil,
            strategy: nil,
            entryPrice: nil,
            exitPrice: nil,
            sessionLabel: nil,
            copyTrade: metadata
        )
    }
}
