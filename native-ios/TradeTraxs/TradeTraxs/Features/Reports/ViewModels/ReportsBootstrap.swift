import Foundation

/// Coordinated Reports catalog first-paint — loads web-parity trading reports.
@MainActor
enum ReportsBootstrap: ScreenBootstrap {
    struct Context {
        var tradingReports: any TradingReportRepository
        var forceNetwork: Bool = false
    }

    struct Result: Equatable {
        var snapshot: TradingReportsSnapshot
        var cards: [ReportTypeCardModel]
        var loadedAt: Date
    }

    static func load(_ context: Context) async throws -> Result {
        let snapshot = try await context.tradingReports.ensureSnapshot(
            forceNetwork: context.forceNetwork
        )
        let cards = TradingReportPeriodKey.allCases.map { key in
            let report = snapshot.report(for: key)
            let availability: ReportAvailability = report == nil ? .readyToGenerate : .ready
            return ReportTypeCardModel(
                periodKey: key,
                title: key.catalogTitle,
                subtitle: report?.dateRangeLabel ?? key.catalogSubtitle,
                systemImage: key.systemImage,
                actionTitle: availability.actionTitle,
                availability: availability,
                dateRangeLabel: report?.dateRangeLabel
            )
        }
        return Result(snapshot: snapshot, cards: cards, loadedAt: Date())
    }
}

/// Detail bootstrap — loads one period report from the shared repository/cache.
@MainActor
enum ReportDetailBootstrap: ScreenBootstrap {
    struct Context {
        var periodKey: TradingReportPeriodKey
        var tradingReports: any TradingReportRepository
        var forceNetwork: Bool = false
    }

    struct Result: Equatable {
        var report: TradingReport
        var blocks: [TradingReportDetailBlock]
        var loadedAt: Date
    }

    static func load(_ context: Context) async throws -> Result {
        let report = try await context.tradingReports.report(
            for: context.periodKey,
            forceNetwork: context.forceNetwork
        )
        return Result(
            report: report,
            blocks: TradingReportDetailBlock.blocks(from: report),
            loadedAt: Date()
        )
    }
}
