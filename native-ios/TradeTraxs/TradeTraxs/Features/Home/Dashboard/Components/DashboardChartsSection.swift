import Charts
import SwiftUI

/// Full-width analytics charts — presentation only over ``DashboardChartMetrics``.
struct DashboardChartsSection: View {
    let summary: DashboardChartMetrics.Summary

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            chartBlock(title: "Trading Sessions") {
                sessionChart
            }
            chartBlock(title: "Weekdays") {
                signedBarChart(summary.weekdays)
            }
            chartBlock(title: "Long vs Short") {
                signedBarChart(summary.longShort)
            }
            if summary.hours.count > 1 {
                chartBlock(title: "Trading Hours") {
                    signedBarChart(summary.hours)
                }
            }
            chartBlock(title: "Win / Loss") {
                winLossChart
            }
            chartBlock(title: "Drawdown") {
                drawdownRow
            }
            if !summary.holdTime.isEmpty {
                chartBlock(title: "Hold Time") {
                    holdTimeRows
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.charts")
    }

    // MARK: - Blocks

    private func chartBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            content()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 140)
        }
        .accessibilityElement(children: .contain)
    }

    private var sessionChart: some View {
        Group {
            if summary.sessions.isEmpty {
                empty("Tag sessions on trades to unlock this breakdown.")
            } else {
                Chart(summary.sessions) { row in
                    BarMark(
                        x: .value("Session", row.label),
                        y: .value("Trades", row.count)
                    )
                    .foregroundStyle(colors.accent.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
            }
        }
    }

    private func signedBarChart(_ points: [DashboardBarPoint]) -> some View {
        Chart(points) { point in
            BarMark(
                x: .value("Label", point.label),
                y: .value("P&L", point.value)
            )
            .foregroundStyle(point.value >= 0 ? colors.profit.gradient : colors.loss.gradient)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
    }

    private var winLossChart: some View {
        Chart(summary.winLoss) { point in
            BarMark(
                x: .value("Result", point.label),
                y: .value("Count", point.count)
            )
            .foregroundStyle(point.label == "Wins" ? colors.profit.gradient : colors.loss.gradient)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
    }

    private var drawdownRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Max drawdown from equity peak")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                Text(DashboardViewModel.money(summary.maxDrawdown))
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(summary.maxDrawdown > 0 ? colors.loss : colors.primaryText)
            }
            Spacer()
            ExperienceIcon(icon: .chart, size: .xl, color: colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.45), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
    }

    private var holdTimeRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(summary.holdTime.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.label)
                        .experienceStyle(.callout, color: colors.secondaryText)
                    Spacer()
                    Text(row.value)
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(colors.primaryText)
                }
                .padding(.vertical, ExperienceSpacing.sm)
                if index < summary.holdTime.count - 1 {
                    Divider().overlay(colors.border.opacity(0.5))
                }
            }
        }
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
