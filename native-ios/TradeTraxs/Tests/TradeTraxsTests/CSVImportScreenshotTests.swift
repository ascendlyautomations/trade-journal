import SwiftUI
import UIKit
import XCTest
@testable import TradeTraxs

/// Renders CSV Import UI surfaces into Docs/Screenshots/CSVImport/ for the experience report.
@MainActor
final class CSVImportScreenshotTests: XCTestCase {
    func testCaptureCSVImportScreenshots() throws {
        let theme = ThemeManager()
        let env = theme.themeEnvironment
        let size = CGSize(width: 390, height: 844)

        try snapshot(
            CSVImportView(viewModel: makeViewModel())
                .applyThemeEnvironment(env),
            name: "01-choose-csv",
            size: size
        )

        let previewVM = makeViewModel()
        let summary = try CSVTradeBuilder.build(
            fileName: "tradovate.csv",
            text: CSVImportFixtures.tradovateCSV
        )
        previewVM.applySummaryForScreenshot(summary)
        try snapshot(
            CSVImportPreviewView(viewModel: previewVM)
                .applyThemeEnvironment(env),
            name: "02-autodetected-preview",
            size: size
        )

        let mappingVM = makeViewModel()
        mappingVM.applyMappingsForScreenshot(
            CSVHeaderAliases.suggestedMappings(for: ["Widget", "Flip", "Beans", "Cash", "When"])
        )
        try snapshot(
            CSVImportMappingView(viewModel: mappingVM)
                .applyThemeEnvironment(env),
            name: "03-manual-mapping",
            size: size
        )

        try snapshot(
            CSVImportTradeReviewView(
                trade: summary.trades[0],
                onSave: { _ in },
                onCancel: {}
            )
            .applyThemeEnvironment(env),
            name: "04-trade-review",
            size: size
        )

        try snapshot(
            CSVImportResultView(
                result: CSVImportResult(
                    importedCount: 3,
                    netPnL: summary.netPnL,
                    skippedInvalidCount: 0,
                    failureMessage: nil
                ),
                onDone: {},
                onAgain: {}
            )
            .applyThemeEnvironment(env),
            name: "05-import-complete",
            size: size
        )
    }

    private func makeViewModel() -> CSVImportViewModel {
        let repository = CSVImportScreenshotStubRepository()
        let cache = DetailPresentationCache()
        let viewer = ProfileID("dev.csv.screenshots")
        cache.seed(accounts: PropFirmFixtures.accounts(owner: viewer), for: viewer)
        return CSVImportViewModel(
            trades: repository,
            session: CSVImportScreenshotStubSession(userID: viewer.rawValue),
            detailCache: cache,
            onDismiss: {}
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

        // Allow SwiftUI to settle one run-loop turn.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(name)")
            return
        }

        let dir = screenshotDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try data.write(to: url, options: .atomic)
        XCTAssertGreaterThan(data.count, 20_000, "Screenshot \(name) looks empty")
        window.isHidden = true
    }

    private func screenshotDirectory() -> URL {
        let file = URL(fileURLWithPath: #filePath)
        let projectRoot = file
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectRoot
            .appendingPathComponent("Docs/Screenshots/CSVImport", isDirectory: true)
    }
}

private struct CSVImportScreenshotStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private final class CSVImportScreenshotStubRepository: TradeRepository, @unchecked Sendable {
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

    func importCSVTrades(
        _ drafts: [TradeDraft],
        isInitialImport: Bool
    ) async throws -> Int {
        drafts.count
    }
}
