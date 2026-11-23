import SwiftUI
import UIKit
import XCTest
@testable import TradeTraxs

@MainActor
final class DashboardEquityCurveStateTests: XCTestCase {
    func testZeroTradesShowsCompactEmptyEquityState() {
        XCTAssertEqual(DashboardEquityCurvePresentation.emptyTitle, "No equity data")
        XCTAssertEqual(DashboardEquityCurvePresentation.emptyDetail, "Equity curve displays after 2 trades.")
        XCTAssertEqual(
            DashboardEquityCurvePresentation.resolve(tradeCount: 0, isChartLoading: false, chartPointCount: 0),
            .compactEmpty
        )
        XCTAssertLessThan(fittedHeight(tradeCount: 0, pointCount: 0, isChartLoading: false), chartHeight() - 200)
    }

    func testOneTradeShowsCompactEmptyEquityState() {
        XCTAssertEqual(
            DashboardEquityCurvePresentation.resolve(tradeCount: 1, isChartLoading: false, chartPointCount: 1),
            .compactEmpty
        )
        XCTAssertLessThan(fittedHeight(tradeCount: 1, pointCount: 1, isChartLoading: false), chartHeight() - 200)
    }

    func testTwoTradesShowsEquityChart() {
        XCTAssertEqual(
            DashboardEquityCurvePresentation.resolve(tradeCount: 2, isChartLoading: false, chartPointCount: 2),
            .chart
        )
        XCTAssertGreaterThan(fittedHeight(tradeCount: 2, pointCount: 2, isChartLoading: false), fittedHeight(tradeCount: 0, pointCount: 0, isChartLoading: false) + 200)
    }

    func testResolvedEmptyEquityIsNotLoading() {
        XCTAssertEqual(
            DashboardEquityCurvePresentation.resolve(tradeCount: 0, isChartLoading: false, chartPointCount: 0),
            .compactEmpty
        )
        XCTAssertNotEqual(
            DashboardEquityCurvePresentation.resolve(tradeCount: 0, isChartLoading: false, chartPointCount: 0),
            .loading
        )
        XCTAssertLessThan(
            fittedHeight(tradeCount: 0, pointCount: 0, isChartLoading: false),
            fittedHeight(tradeCount: 0, pointCount: 0, isChartLoading: true) - 200
        )
    }

    func testHoldHistogramRendersVisibleBarPixelsOnLoad() {
        let root = holdHistogram
            .frame(width: 390)
            .padding()
            .applyThemeEnvironment(.fallback)
            .preferredColorScheme(.dark)

        let size = CGSize(width: 390, height: 240)
        let host = UIHostingController(rootView: root)
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = UIColor(red: 11 / 255, green: 18 / 255, blue: 24 / 255, alpha: 1)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let plotRect = CGRect(x: 40, y: 20, width: 330, height: 140)
        let accentPixelCount = countAccentBarPixels(in: image, within: plotRect)
        XCTAssertGreaterThan(
            accentPixelCount,
            120,
            "Expected solid hold-time bar pixels in plot area, found \(accentPixelCount)"
        )
        window.isHidden = true
    }

    private func countAccentBarPixels(in image: UIImage, within rect: CGRect) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        let scaleX = CGFloat(pixelWidth) / 390
        let scaleY = CGFloat(pixelHeight) / 240

        let x0 = Int(rect.minX * scaleX)
        let x1 = Int(rect.maxX * scaleX)
        let y0 = Int(rect.minY * scaleY)
        let y1 = Int(rect.maxY * scaleY)

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var count = 0
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            guard let context = CGContext(
                data: base,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in y0..<min(y1, pixelHeight) {
                for x in x0..<min(x1, pixelWidth) {
                    let offset = (y * pixelWidth + x) * 4
                    let r = CGFloat(bytes[offset])
                    let g = CGFloat(bytes[offset + 1])
                    let b = CGFloat(bytes[offset + 2])
                    let a = CGFloat(bytes[offset + 3])
                    guard a > 180 else { continue }
                    let chroma = max(g, b) - min(r, min(g, b))
                    if g > 110, b > 120, chroma > 45, g + b > r * 2 {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    func testDashboardSectionsFitProposedWidth() {
        // Screen widths, plus the width a chart actually receives inside the
        // dashboard card (screen minus section and card padding).
        let widths: [CGFloat] = [256, 320, 326, 329, 338, 366, 390, 393, 402, 430]
        let sections: [(String, AnyView)] = [
            ("equity", AnyView(equityChart)),
            ("hours", AnyView(hourTimeline)),
            ("hold", AnyView(holdHistogram)),
            ("metrics", AnyView(metricStrip)),
            ("weekdays", AnyView(weekdayHeatmap)),
            ("sessions", AnyView(sessionBars)),
            ("winLoss", AnyView(winLossRing)),
            ("symbols", AnyView(symbolBars)),
            ("drawdown", AnyView(drawdownChart)),
            ("direction", AnyView(longShortComparison)),
        ]
        for width in widths {
            for (name, section) in sections {
                let fitted = fittedWidth(section, proposed: width)
                XCTAssertLessThanOrEqual(
                    fitted,
                    width,
                    "\(name) fitted \(fitted) at \(width)"
                )
            }
        }
    }

    private var equityChart: some View {
        DashboardEquityHero(
            summary: equitySummary(tradeCount: 8, points: sampleEquity),
            periodTitle: "All Time",
            chartPoints: sampleEquity,
            isChartLoading: false
        )
    }

    private var sampleEquity: [ProfileStatisticsMetrics.EquityPoint] {
        (0..<8).map { index in
            ProfileStatisticsMetrics.EquityPoint(index: index, equity: Decimal(10_000 + index * 250))
        }
    }

    private var metricStrip: some View {
        DashboardMetricStrip(chips: [
            DashboardMetricChip(id: "pnl", label: "Net P&L", value: "+$12,480.55", tone: .positive),
            DashboardMetricChip(id: "wr", label: "Win Rate", value: "68%", tone: .neutral),
            DashboardMetricChip(id: "pf", label: "Profit Factor", value: "2.41", tone: .neutral),
            DashboardMetricChip(id: "exp", label: "Expectancy", value: "+$186.20", tone: .positive),
        ])
    }

    private var hourTimeline: some View {
        DashboardHourTimelineView(
            points: (0..<24).map { DashboardBarPoint(label: String(format: "%02d", $0), value: Double($0)) }
        )
    }

    private var holdHistogram: some View {
        DashboardHoldHistogramView(
            buckets: holdHistogramBuckets,
            averages: [
                DashboardHoldTimeRow(label: "Average", value: "42m"),
                DashboardHoldTimeRow(label: "Median", value: "18m"),
                DashboardHoldTimeRow(label: "Longest", value: "6h 12m"),
            ]
        )
    }

    private var weekdayHeatmap: some View {
        DashboardWeekdayHeatmapView(
            points: [
                DashboardBarPoint(label: "Mon", value: 12_480.55),
                DashboardBarPoint(label: "Tue", value: -8_420.10),
                DashboardBarPoint(label: "Wed", value: 640),
                DashboardBarPoint(label: "Thu", value: -220.5),
                DashboardBarPoint(label: "Fri", value: 1_100),
                DashboardBarPoint(label: "Sat", value: 0),
                DashboardBarPoint(label: "Sun", value: 80),
            ]
        )
    }

    private var sessionBars: some View {
        DashboardSessionBarsView(
            performance: [
                DashboardSessionPerformanceRow(label: "London", tradeCount: 12, netPnL: 4_280.25, wins: 8, losses: 4, winRate: 66),
                DashboardSessionPerformanceRow(label: "NY", tradeCount: 18, netPnL: -1_540.80, wins: 7, losses: 11, winRate: 39),
                DashboardSessionPerformanceRow(label: "Asia", tradeCount: 6, netPnL: 320, wins: 4, losses: 2, winRate: 67),
            ]
        )
    }

    private var winLossRing: some View {
        DashboardWinLossRingView(winCount: 42, lossCount: 19)
    }

    private var symbolBars: some View {
        DashboardSymbolRankedBarsView(rows: [
            DashboardSymbolPerformanceRow(ticker: "MNQ", trades: 20, netPnL: 8_420.55, winRate: 0.7, avgRR: 1.8),
            DashboardSymbolPerformanceRow(ticker: "MES", trades: 11, netPnL: -2_140.25, winRate: 0.4, avgRR: 0.8),
        ])
    }

    private var drawdownChart: some View {
        DashboardUnderwaterDrawdownView(
            series: (0..<12).map { DashboardDrawdownPoint(index: $0, depth: Double($0) * -10) },
            maxDrawdown: 120
        )
    }

    private var longShortComparison: some View {
        DashboardLongShortComparisonView(
            comparison: DashboardLongShortComparison(
                long: DashboardDirectionSideSnapshot(
                    trades: 24, netPnL: 6_420.55, wins: 16, losses: 8, winRate: 66,
                    profitFactor: 2.1, expectancy: 180, avgRR: 1.6, bestTrade: 900, worstTrade: -300
                ),
                short: DashboardDirectionSideSnapshot(
                    trades: 18, netPnL: -1_240.10, wins: 7, losses: 11, winRate: 39,
                    profitFactor: 0.8, expectancy: -40, avgRR: 0.9, bestTrade: 400, worstTrade: -700
                )
            )
        )
    }

    private var holdHistogramBuckets: [DashboardHistogramBucket] {
        [
            DashboardHistogramBucket(label: "<5m", count: 4, totalNetPnL: 1_280),
            DashboardHistogramBucket(label: "5–15m", count: 4, totalNetPnL: -720),
            DashboardHistogramBucket(label: "15–60m", count: 4, totalNetPnL: 2_560),
            DashboardHistogramBucket(label: "1–4h", count: 4, totalNetPnL: -360),
            DashboardHistogramBucket(label: "4h+", count: 4, totalNetPnL: 4_800),
        ]
    }

    private func fittedWidth<V: View>(_ view: V, proposed: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view)
        host.view.bounds = CGRect(x: 0, y: 0, width: proposed, height: 1)
        return host.sizeThatFits(in: CGSize(width: proposed, height: 4000)).width
    }

    func testUnresolvedEquityStaysLoading() {
        XCTAssertEqual(
            DashboardEquityCurvePresentation.resolve(tradeCount: 0, isChartLoading: true, chartPointCount: 0),
            .loading
        )
    }

    private func chartHeight() -> CGFloat {
        fittedHeight(tradeCount: 2, pointCount: 2, isChartLoading: false)
    }

    private func fittedHeight(tradeCount: Int, pointCount: Int, isChartLoading: Bool) -> CGFloat {
        let points = (0..<pointCount).map { index in
            ProfileStatisticsMetrics.EquityPoint(index: index, equity: Decimal(index + 1) * 100)
        }
        let root = DashboardEquityHero(
            summary: equitySummary(tradeCount: tradeCount, points: points),
            periodTitle: "All",
            chartPoints: points,
            isChartLoading: isChartLoading
        )
        let host = UIHostingController(rootView: root)
        host.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 1)
        let size = host.sizeThatFits(in: CGSize(width: 390, height: UIView.layoutFittingExpandedSize.height))
        return size.height
    }

    private func equitySummary(
        tradeCount: Int,
        points: [ProfileStatisticsMetrics.EquityPoint]
    ) -> DashboardChartMetrics.Summary {
        DashboardChartMetrics.Summary(
            netPnL: 0,
            winRate: nil,
            profitFactor: nil,
            payouts: nil,
            expectancy: nil,
            averageRR: nil,
            averageMaxRrReached: nil,
            rrTargetAnalysis: DashboardRrTargetAnalysis(
                tradeCount: 0,
                pairedCount: 0,
                pairedNonPositiveCount: 0,
                pairedPositiveCount: 0,
                avgTargetRr: nil,
                avgMaxRrReached: nil,
                avgTargetAttainmentRatio: nil,
                sampleSummary: nil,
                headline: nil,
                bullets: []
            ),
            tradeCount: tradeCount,
            winCount: 0,
            lossCount: 0,
            avgWin: nil,
            avgLoss: nil,
            bestTrade: nil,
            biggestLoss: nil,
            maxDrawdown: 0,
            currentEquity: points.last?.equity ?? 0,
            equityData: points,
            sessions: [],
            weekdays: [],
            hours: [],
            longShort: [],
            longTradeCount: 0,
            shortTradeCount: 0,
            winLoss: [],
            holdTime: [],
            holdTimeHistogram: [],
            drawdownSeries: [],
            weekdayHeatmap: [],
            hourHeatmap: [],
            insights: [],
            sessionPerformance: [],
            symbolPerformance: [],
            dailyPerformance: nil,
            streaks: nil,
            hourHighlights: nil,
            longShortComparison: nil,
            holdExtremes: [],
            strategyHighlights: nil
        )
    }
}
