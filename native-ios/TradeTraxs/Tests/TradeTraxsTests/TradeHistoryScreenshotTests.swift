import SwiftUI
import UIKit
import XCTest
@testable import TradeTraxs

@MainActor
final class TradeHistoryScreenshotTests: XCTestCase {
    func testCaptureTradesScreenshots() throws {
        let theme = ThemeManager()
        let env = theme.themeEnvironment
        let size = CGSize(width: 390, height: 844)
        let pipeline = TradeHistoryStubImagePipeline()

        // 1) Dashboard with Calendar (nav) + Trades filter-bar shortcut
        let dashStore = NavigationStore()
        let dashCoordinator = NavigationCoordinator(store: dashStore)
        let dashVM = DashboardViewModel(
            home: TradeHistoryScreenshotHomeRepository(),
            trades: TradeHistoryScreenshotTradeRepository(),
            achievements: TradeHistoryScreenshotAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: TradeHistoryScreenshotSession(userID: "dev.trades.shots"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: dashCoordinator
        )
        dashVM.loadIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try snapshot(
            DashboardHomeView(
                viewModel: dashVM,
                navigationCoordinator: dashCoordinator
            )
            .applyThemeEnvironment(env),
            name: "01-dashboard-calendar-trades",
            size: size
        )

        // 2) Trades default (journal cards)
        let tradesVM = makeTradesVM()
        tradesVM.loadIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try snapshot(
            TradeHistoryView(
                viewModel: tradesVM,
                imagePipeline: pipeline
            )
            .applyThemeEnvironment(env),
            name: "02-trades-default",
            size: size
        )

        // 3) Active filters
        let filteredVM = makeTradesVM()
        filteredVM.loadIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        filteredVM.filters.result = .wins
        filteredVM.filters.dateRange = .thisMonth
        filteredVM.filters.direction = .long
        Task { await filteredVM.refresh() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try snapshot(
            TradeHistoryView(
                viewModel: filteredVM,
                imagePipeline: pipeline
            )
            .applyThemeEnvironment(env),
            name: "03-trades-active-filters",
            size: size
        )

        // 4) Filter sheet
        let sheetVM = makeTradesVM()
        sheetVM.draftFilters = sheetVM.filters
        sheetVM.draftFilters.pnlMin = 100
        sheetVM.draftFilters.pnlMax = 500
        sheetVM.draftFilters.result = .wins
        try snapshot(
            TradeHistoryFilterSheet(viewModel: sheetVM)
                .applyThemeEnvironment(env),
            name: "04-filter-sheet",
            size: size
        )

        // 5) P&L filter emphasis
        sheetVM.draftFilters = TradeHistoryFilters()
        sheetVM.draftFilters.pnlMin = 200
        sheetVM.draftFilters.pnlMax = nil
        sheetVM.draftFilters.result = .any
        try snapshot(
            TradeHistoryFilterSheet(viewModel: sheetVM)
                .applyThemeEnvironment(env),
            name: "05-pnl-filter",
            size: size
        )

        // 6) Empty / no-results
        let emptyVM = makeTradesVM()
        emptyVM.loadIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        emptyVM.filters.pnlMin = 9_999_999
        Task { await emptyVM.refresh() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try snapshot(
            TradeHistoryView(
                viewModel: emptyVM,
                imagePipeline: pipeline
            )
            .applyThemeEnvironment(env),
            name: "06-no-results",
            size: size
        )
    }

    private func makeTradesVM() -> TradeHistoryViewModel {
        TradeHistoryViewModel(
            trades: TradeHistoryScreenshotTradeRepository(),
            session: TradeHistoryScreenshotSession(userID: "dev.trades.shots"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
    }

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize) throws {
        let root = NavigationStack { view }
            .frame(width: size.width, height: size.height)
        let host = UIHostingController(rootView: root)
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .systemBackground

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(name)")
            return
        }
        let dir = screenshotDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
        XCTAssertGreaterThan(data.count, 20_000, "Screenshot \(name) looks empty")
        window.isHidden = true
    }

    private func screenshotDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Docs/Screenshots/Trades", isDirectory: true)
    }
}

private struct TradeHistoryScreenshotSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }
    var accessToken: String? { get async { "token" } }
}

private struct TradeHistoryScreenshotHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        HomeDashboard(
            summary: PerformanceSummary(
                interval: DateIntervalValue(start: Date(), end: Date()),
                statistics: TradeStatistics(
                    tradeCount: 0,
                    winCount: 0,
                    lossCount: 0,
                    totalPnL: Money(amount: 0),
                    averagePnL: Money(amount: 0),
                    averageRiskReward: nil,
                    winRate: 0
                ),
                bestTradeID: nil,
                worstTradeID: nil,
                currentStreakDays: 0
            ),
            widgets: [],
            insights: [],
            shortcutDestinations: [],
            refreshedAt: Date()
        )
    }

    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary {
        try await dashboard(for: profileID).summary
    }
}

private struct TradeHistoryScreenshotAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.unknown(message: "not found")
    }

    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ achievement: Achievement) async throws -> Achievement { achievement }
}

private final class TradeHistoryScreenshotTradeRepository: TradeRepository, @unchecked Sendable {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: ProfileTradeFixtures.samples(owner: profileID), nextCursor: nil)
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

private struct TradeHistoryStubImagePipeline: ImagePipeline {
    func data(for request: ImageRequest) async throws -> Data {
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5W7W0AAAAASUVORK5CYII="
        return Data(base64Encoded: pngBase64) ?? Data()
    }

    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}
