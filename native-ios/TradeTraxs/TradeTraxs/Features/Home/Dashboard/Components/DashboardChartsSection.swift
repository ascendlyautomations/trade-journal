import SwiftUI

/// Full-width analytics charts — Phase 2 visuals + Phase 3 interactions.
///
/// Flow: Win/Loss → Behavior (sessions → weekdays → direction → hours) →
/// Execution (hold) → Risk (drawdown).
struct DashboardChartsSection: View {
    let summary: DashboardChartMetrics.Summary
    var onBrowseWins: (() -> Void)?
    var onBrowseLosses: (() -> Void)?
    var onBrowseSession: ((String) -> Void)?
    var onBrowseWeekday: ((String) -> Void)?
    var onBrowseHour: ((String) -> Void)?
    var onBrowseLong: (() -> Void)?
    var onBrowseShort: (() -> Void)?
    var onBrowseHoldBucket: ((String) -> Void)?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxl) {
            chartBlock(
                title: "Win / Loss",
                subtitle: "Tap Wins or Losses to open matching trades"
            ) {
                DashboardWinLossRingView(
                    winCount: summary.winCount,
                    lossCount: summary.lossCount,
                    onSelectWins: onBrowseWins,
                    onSelectLosses: onBrowseLosses
                )
            }

            behaviorGroup
            executionGroup
            riskGroup
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.charts")
    }

    private var behaviorGroup: some View {
        sectionGroup(title: "Behavior") {
            chartBlock(
                title: "Trading Sessions",
                subtitle: "Tap a session to browse those trades"
            ) {
                DashboardSessionBarsView(
                    sessions: summary.sessions,
                    onSelect: onBrowseSession
                )
            }
            chartBlock(
                title: "Weekdays",
                subtitle: "Tap a day to filter the journal"
            ) {
                DashboardWeekdayHeatmapView(
                    points: summary.weekdayHeatmap,
                    onSelect: onBrowseWeekday
                )
            }
            chartBlock(
                title: "Long vs Short",
                subtitle: "Tap Long or Short to open the journal"
            ) {
                DashboardLongShortDonutView(
                    longCount: summary.longTradeCount,
                    shortCount: summary.shortTradeCount,
                    longPnL: summary.longShort.first(where: { $0.label == "Long" })?.value ?? 0,
                    shortPnL: summary.longShort.first(where: { $0.label == "Short" })?.value ?? 0,
                    onSelectLong: onBrowseLong,
                    onSelectShort: onBrowseShort
                )
            }
            if summary.hourHeatmap.contains(where: { abs($0.value) > 0.01 }) {
                chartBlock(
                    title: "Trading Hours",
                    subtitle: "Tap an hour to inspect that window"
                ) {
                    DashboardHourTimelineView(
                        points: summary.hourHeatmap,
                        onSelect: onBrowseHour
                    )
                }
            }
        }
    }

    private var executionGroup: some View {
        sectionGroup(title: "Execution") {
            chartBlock(
                title: "Hold Time",
                subtitle: summary.holdTimeHistogram.isEmpty
                    ? nil
                    : "Select a bar to view matching holds"
            ) {
                if summary.holdTimeHistogram.isEmpty {
                    DashboardChartEmptyCopy(
                        message: "Your hold time distribution will appear after more completed trades."
                    )
                } else {
                    DashboardHoldHistogramView(
                        buckets: summary.holdTimeHistogram,
                        averages: summary.holdTime,
                        onSelectBucket: onBrowseHoldBucket
                    )
                }
            }
        }
    }

    private var riskGroup: some View {
        sectionGroup(title: "Risk") {
            chartBlock(title: "Drawdown", subtitle: "Drag the curve to inspect depth") {
                DashboardUnderwaterDrawdownView(
                    series: summary.drawdownSeries,
                    maxDrawdown: summary.maxDrawdown
                )
            }
        }
    }

    private func sectionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
                content()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    private func chartBlock<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .fontWeight(.medium)
                if let subtitle {
                    Text(subtitle)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExperienceSpacing.md)
                .background(colors.fillSecondary.opacity(0.28), in: RoundedRectangle(
                    cornerRadius: ExperienceRadius.md,
                    style: .continuous
                ))
                .transition(
                    .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                )
        }
        .accessibilityElement(children: .contain)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: summary.tradeCount
        )
    }
}
