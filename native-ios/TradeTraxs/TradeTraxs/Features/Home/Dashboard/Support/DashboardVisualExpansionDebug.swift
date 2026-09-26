#if DEBUG
import Foundation

/// Temporary DEBUG probe for Dashboard V3 visual expansion pipeline (remove after QA sign-off).
enum DashboardVisualExpansionDebug {
    static func logPipeline(
        path: String,
        v3: Bool,
        grdb: Bool,
        chartOverlayLoaded: Bool,
        revision: Int64,
        preset: String,
        distributions: AnalyticsDashboardDistributionsWireV1?,
        summary: DashboardChartMetrics.Summary
    ) {
        let dist = distributions
        let expansionReceived = dist.map(DashboardAnalyticsChartsSupport.distributionsIncludeVisualExpansion) ?? false
        print(
            """
            [DashboardVisualExpansion]
            path=\(path) v3=\(v3) grdb=\(grdb) chartOverlayLoaded=\(chartOverlayLoaded) \
            revision=\(revision) preset=\(preset)
            expansionContractInDistributions=\(expansionReceived)
            dailyPerformance=\(summary.dailyPerformance != nil)
            streaks=\(summary.streaks != nil)
            sessionPerformanceRows=\(summary.sessionPerformance.count) \
            sessionPnLNonZero=\(summary.sessionPerformance.contains { $0.netPnL != 0 })
            longShortComparison=\(summary.longShortComparison != nil)
            hourHighlights=\(summary.hourHighlights != nil)
            symbols=\(summary.symbolPerformance.count)
            setups=\(summary.strategyHighlights != nil)
            holdExtremes=\(summary.holdExtremes.count)
            """
        )
        logSectionVisibility(summary: summary)
    }

    static func logSectionVisibility(summary: DashboardChartMetrics.Summary) {
        let consistency = summary.dailyPerformance != nil || summary.streaks != nil
        let longShort = summary.longShortComparison.map {
            $0.long != nil || $0.short != nil
        } ?? false
        let symbols = !summary.symbolPerformance.isEmpty
        let setups = summary.strategyHighlights.map {
            $0.best != nil || $0.worst != nil
        } ?? false
        print(
            """
            [DashboardVisualExpansion][sections]
            consistencyAndStreaks=\(consistency)
            sessionPnLBars=\(!summary.sessionPerformance.isEmpty)
            longShortComparison=\(longShort)
            symbolPerformance=\(symbols)
            setupPerformance=\(setups)
            holdExtremes=\(!summary.holdExtremes.isEmpty)
            """
        )
    }

    static func logStaleChartsCache(scope: String, revision: Int64) {
        print(
            "[DashboardVisualExpansion] staleChartsCache scope=\(scope) revision=\(revision) — refetching charts RPC"
        )
    }
}
#endif
