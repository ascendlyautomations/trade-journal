import SwiftUI

private enum TradeDetailLayout {
    static let sectionSpacing: CGFloat = ExperienceSpacing.md
    static let groupSpacing: CGFloat = ExperienceSpacing.xs
    static let surfacePadding: CGFloat = ExperienceSpacing.sm
}

// MARK: - Compact header

struct TradeDetailCompactHeader: View {
    let trade: Trade
    var accountLine: String?
    var showsEdit: Bool = false
    var onEdit: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var pnlAmount: Double {
        NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TradeDisplay.tickerText(trade.symbol))
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)

                    Text(TradeDisplay.sideTitle(trade.side).uppercased())
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(trade.side == .long ? colors.profit : colors.loss)

                    Text(TradeDisplay.dateTimeText(trade.entryAt))
                        .experienceStyle(.caption2, color: colors.secondaryText)
                }

                Spacer(minLength: ExperienceSpacing.xs)

                VStack(alignment: .trailing, spacing: 2) {
                    if showsEdit, let onEdit {
                        TradeDetailCompactEditButton(action: onEdit)
                    }

                    Text(TradeDisplay.pnlText(trade.realizedPnL))
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(theme.metricColor(for: pnlAmount))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let rr = TradeDisplay.compactRRText(trade.riskReward) {
                        Text(rr)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.secondaryText)
                    }
                }
            }

            if let accountLine, !accountLine.isEmpty {
                Text(accountLine)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TradeDetailCompactEditButton: View {
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                Text("Edit")
                    .font(.system(.caption, design: .default).weight(.semibold))
            }
            .foregroundStyle(colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                colors.accent.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.trade.editButton")
    }
}

// MARK: - Grouped surfaces

struct TradeDetailGroupedSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        content()
            .padding(TradeDetailLayout.surfacePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                colors.fillSecondary.opacity(0.45),
                in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            )
    }
}

struct TradeDetailSectionHeader: View {
    let title: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(title)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.35)
    }
}

// MARK: - Quick stats

struct TradeDetailQuickStatsSection: View {
    let trade: Trade

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var pnlTone: Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
        )
    }

    var body: some View {
        TradeDetailGroupedSurface {
            VStack(spacing: TradeDetailLayout.groupSpacing) {
                TradeDetailCompactStatRow(cells: [
                    TradeDetailStatCell(
                        label: "Entry",
                        value: TradeDisplay.priceText(trade.entryPrice),
                        subtitle: TradeDisplay.entryExecutionTimeText(for: trade)
                    ),
                    TradeDetailStatCell(
                        label: "Exit",
                        value: TradeDisplay.priceText(trade.exitPrice),
                        subtitle: TradeDisplay.exitExecutionTimeText(for: trade)
                    ),
                    TradeDetailStatCell(
                        label: "Contracts",
                        value: TradeDisplay.contractsText(trade.quantity)
                    ),
                ])

                TradeDetailStatDivider()

                TradeDetailCompactStatRow(cells: [
                    TradeDetailStatCell(
                        label: "P&L",
                        value: TradeDisplay.pnlText(trade.realizedPnL),
                        valueColor: pnlTone
                    ),
                    TradeDetailStatCell(
                        label: "RR",
                        value: TradeDisplay.compactRRText(trade.riskReward) ?? "—"
                    ),
                    TradeDetailStatCell(
                        label: "Hold",
                        value: TradeDisplay.holdDuration(for: trade) ?? "—"
                    ),
                ])
            }
        }
        .accessibilityIdentifier("detail.trade.quickStats")
    }
}

private struct TradeDetailStatCell {
    var label: String
    var value: String
    var valueColor: Color?
    var subtitle: String?
}

private struct TradeDetailCompactStatRow: View {
    let cells: [TradeDetailStatCell]

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.xs) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(cell.value)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(cell.valueColor ?? colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let subtitle = cell.subtitle {
                        Text(subtitle)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct TradeDetailStatDivider: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        Rectangle()
            .fill(colors.separator.opacity(0.6))
            .frame(height: 0.5)
    }
}

// MARK: - Comparison

struct TradeDetailComparisonSection: View {
    let trade: Trade
    let cohort: TradeDetailAnalytics.CohortComparison
    var quickInsight: TradeDetailAnalytics.QuickInsight?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
            TradeDetailSectionHeader(title: "Compared to Your Trades")

            TradeDetailGroupedSurface {
                VStack(spacing: TradeDetailLayout.groupSpacing) {
                    comparisonHeaderRow

                    comparisonRow(
                        label: "P&L",
                        thisValue: TradeDisplay.pnlText(trade.realizedPnL),
                        avgValue: TradeDisplay.pnlText(Money(amount: cohort.avgPnL)),
                        thisTone: theme.metricColor(
                            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                        )
                    )

                    if let tradeRR = trade.riskReward, let avgRR = cohort.avgRR {
                        comparisonRow(
                            label: "RR",
                            thisValue: TradeDisplay.compactRRText(tradeRR) ?? "—",
                            avgValue: TradeDisplay.compactRRText(avgRR) ?? "—"
                        )
                    }

                    if let tradeHold = TradeDetailAnalytics.holdSeconds(for: trade),
                       let avgHold = cohort.avgHoldSeconds
                    {
                        comparisonRow(
                            label: "Hold",
                            thisValue: TradeDisplay.compactHoldDuration(seconds: tradeHold) ?? "—",
                            avgValue: TradeDisplay.compactHoldDuration(seconds: avgHold) ?? "—"
                        )
                    }

                    if let insightText = primaryInsight {
                        Text(insightText)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityIdentifier("detail.trade.comparison")
    }

    private var comparisonHeaderRow: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("THIS")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .frame(width: 72, alignment: .trailing)
            Text("AVG")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func comparisonRow(
        label: String,
        thisValue: String,
        avgValue: String,
        thisTone: Color? = nil
    ) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Text(label)
                .experienceStyle(.caption, color: colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(thisValue)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(thisTone ?? colors.primaryText)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(avgValue)
                .font(.system(.subheadline, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(colors.secondaryText)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var primaryInsight: String? {
        if let quickInsight {
            return "↑ \(quickInsight.message)"
        }
        return cohort.findings.first.map { "↑ \($0)" }
    }
}

// MARK: - Ticker history

struct TradeDetailTickerHistorySection: View {
    let history: TradeDetailAnalytics.TickerHistory

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
            TradeDetailSectionHeader(title: "Your \(history.ticker) History")

            TradeDetailGroupedSurface {
                VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
                    if history.previousTradeCount > 0 {
                        Text(summaryMetricsLine)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        if let avgTrade = history.avgTradePnL {
                            Text("Avg Trade \(TradeDisplay.pnlText(Money(amount: avgTrade)))")
                                .font(.system(.caption, design: .rounded).weight(.medium).monospacedDigit())
                                .foregroundStyle(
                                    theme.metricColor(for: NSDecimalNumber(decimal: avgTrade).doubleValue)
                                )
                        }
                    }

                    Text(history.comparisonSentence)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("detail.trade.tickerHistory")
    }

    private var summaryMetricsLine: String {
        var parts: [String] = ["\(history.previousTradeCount) Previous Trades"]
        if let winRate = history.winRate {
            parts.append(String(format: "%.0f%% Win", NSDecimalNumber(decimal: winRate * 100).doubleValue))
        }
        if let profitFactor = history.profitFactor {
            parts.append(String(format: "%.1f PF", NSDecimalNumber(decimal: profitFactor).doubleValue))
        }
        parts.append(TradeDisplay.pnlText(Money(amount: history.totalPnL)))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Journal

struct TradeDetailJournalSection: View {
    let trade: Trade
    let notes: [TradeNote]
    var isOwner: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        if detailRows.isEmpty, noteBodies.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
                if !detailRows.isEmpty {
                    VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
                        TradeDetailSectionHeader(title: "Details")
                        TradeDetailGroupedSurface {
                            VStack(spacing: 6) {
                                ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                                    detailRow(label: row.0, value: row.1)
                                    if index < detailRows.count - 1 {
                                        TradeDetailStatDivider()
                                    }
                                }
                            }
                        }
                    }
                }

                if !noteBodies.isEmpty {
                    VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
                        TradeDetailSectionHeader(title: "Notes")
                        TradeDetailGroupedSurface {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                                ForEach(Array(noteBodies.enumerated()), id: \.offset) { index, body in
                                    Text(body)
                                        .experienceStyle(.subheadline, color: colors.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if index < noteBodies.count - 1 {
                                        TradeDetailStatDivider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("detail.trade.journal")
        }
    }

    private var noteBodies: [String] {
        notes
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var detailRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let setup = trade.strategy?.trimmingCharacters(in: .whitespacesAndNewlines), !setup.isEmpty {
            rows.append(("Setup", setup))
        }
        if let session = trade.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            rows.append(("Session", session))
        }
        if let timeframe = trade.timeframe?.trimmingCharacters(in: .whitespacesAndNewlines), !timeframe.isEmpty {
            rows.append(("Timeframe", timeframe))
        }
        if let emotion = trade.emotion?.trimmingCharacters(in: .whitespacesAndNewlines), !emotion.isEmpty {
            rows.append(("Emotion", emotion))
        }
        if let confidence = trade.confidence {
            rows.append(("Confidence", "\(confidence)/5"))
        }
        if let followed = trade.followedPlan {
            rows.append(("Followed Plan", followed ? "Yes" : "No"))
        }
        if let market = trade.marketCondition?.trimmingCharacters(in: .whitespacesAndNewlines), !market.isEmpty {
            rows.append(("Market", market))
        }
        if let exitEmotion = trade.exitEmotion?.trimmingCharacters(in: .whitespacesAndNewlines), !exitEmotion.isEmpty {
            rows.append(("Exit Emotion", exitEmotion))
        }
        if let rating = trade.executionRating {
            rows.append(("Execution", "\(rating)/5"))
        }
        if let psych = trade.psychologyNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !psych.isEmpty {
            rows.append(("Psychology", psych))
        }
        if isOwner {
            rows.append(("Visibility", trade.visibility == .public ? "Public" : "Private"))
        }
        return rows
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            Text(label)
                .experienceStyle(.caption, color: colors.tertiaryText)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
