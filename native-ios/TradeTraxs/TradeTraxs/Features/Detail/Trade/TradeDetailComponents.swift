import SwiftUI

private enum TradeDetailLayout {
    static let sectionSpacing: CGFloat = ExperienceSpacing.md
    static let groupSpacing: CGFloat = ExperienceSpacing.xs
    /// Space between journal detail blocks (Setup, Execution, etc.), reads as separate cards on the page.
    static let journalBlockSpacing: CGFloat = ExperienceSpacing.md
    static let cardCornerRadius: CGFloat = ExperienceRadius.sm

    static func surfacePadding(colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .light ? ExperienceSpacing.md : ExperienceSpacing.sm
    }

    static func detailRowVerticalPadding(colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .light ? ExperienceSpacing.xxs : 0
    }
}

// MARK: - Compact header

struct TradeDetailCompactHeader: View {
    let trade: Trade
    var accountLine: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var pnlAmount: Double {
        NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(TradeDisplay.tickerText(trade.symbol))
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)

                    Text(TradeDisplay.sideTitle(trade.side).uppercased())
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(trade.side == .long ? colors.profit : colors.loss)

                    if let range = TradeDisplay.journalTradeDetailExecutionRangeText(for: trade) {
                        Text(range)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: ExperienceSpacing.xs)

                VStack(alignment: .trailing, spacing: ExperienceSpacing.xxs) {
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

                    TradeJournalVisibilityLabel(visibility: trade.visibility)
                        .accessibilityIdentifier("detail.trade.visibility")
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

// MARK: - Social (public) header

struct SocialTradeDetailHeader: View {
    let trade: Trade
    var accountBadge: String?
    var copyTradeSummary: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var pnlAmount: Double {
        NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xxs) {
                        Text(TradeDisplay.tickerText(trade.symbol))
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)

                        if let accountBadge, !accountBadge.isEmpty {
                            Text("|")
                                .font(.system(.subheadline, design: .default).weight(.medium))
                                .foregroundStyle(colors.tertiaryText)
                            Text(accountBadge)
                                .font(.system(.subheadline, design: .default).weight(.medium))
                                .foregroundStyle(colors.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }

                    Text(TradeDisplay.sideTitle(trade.side).uppercased())
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(trade.side == .long ? colors.profit : colors.loss)
                }

                Spacer(minLength: ExperienceSpacing.xs)

                VStack(alignment: .trailing, spacing: ExperienceSpacing.xxs) {
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

            if let copyTradeSummary, !copyTradeSummary.isEmpty {
                Text(copyTradeSummary)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SocialTradePublicCaptionSection: View {
    let caption: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(caption)
            .experienceStyle(.subheadline, color: colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("detail.trade.publicCaption")
    }
}

struct SocialTradePublicMetricsSection: View {
    let trade: Trade

    var body: some View {
        TradeDetailGroupedSurface(plainGroupedBackgroundInDarkMode: true) {
            TradeExecutionMetricsTwoRowGrid(
                trade: trade,
                contentAlignment: .centered,
                showsPoints: false,
                showsSocialExecutionDates: true
            )
        }
        .accessibilityIdentifier("detail.trade.socialMetrics")
    }
}

struct SocialTradeDetailMediaSection: View {
    let tradeID: TradeID
    let mediaReference: MediaReference?
    let linkedReel: Reel?
    let imagePipeline: any ImagePipeline
    var onDoubleTapLike: (() -> Void)? = nil
    var onOpenLinkedClip: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if mediaReference != nil || linkedReel != nil {
            if let mediaReference {
                ZStack(alignment: .bottomTrailing) {
                    TradeDetailMediaView(
                        mediaID: tradeID.rawValue,
                        reference: mediaReference,
                        imagePipeline: imagePipeline,
                        onDoubleTapLike: onDoubleTapLike
                    )

                    if let linkedReel, let onOpenLinkedClip {
                        FeedLinkedClipImageOverlay(
                            reel: linkedReel,
                            imagePipeline: imagePipeline,
                            onOpen: onOpenLinkedClip
                        )
                        .padding(ExperienceSpacing.sm)
                    }
                }
                .accessibilityIdentifier("detail.trade.mediaWithClip")
            } else if let linkedReel, let onOpenLinkedClip {
                FeedLinkedClipEmbed(
                    reel: linkedReel,
                    imagePipeline: imagePipeline,
                    onOpen: onOpenLinkedClip,
                    showsDuration: false,
                    thumbnailSide: 76
                )
                .accessibilityIdentifier("detail.trade.linkedClipOnly")
            }
        }
    }
}

// MARK: - Grouped surfaces

struct TradeDetailGroupedSurface<Content: View>: View {
    /// When true, social trade detail metrics sit flush on the screen background in dark mode.
    var plainGroupedBackgroundInDarkMode: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    private var showsGroupedCardBackground: Bool {
        if plainGroupedBackgroundInDarkMode && colorScheme == .dark {
            return false
        }
        return true
    }

    var body: some View {
        let padded = content()
            .padding(TradeDetailLayout.surfacePadding(colorScheme: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)

        if showsGroupedCardBackground {
            if colorScheme == .light {
                padded.experienceTradingRulesCard(cornerRadius: TradeDetailLayout.cardCornerRadius)
            } else {
                padded.background {
                    colors.fillSecondary.opacity(0.45)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: TradeDetailLayout.cardCornerRadius,
                                style: .continuous
                            )
                        )
                }
            }
        } else {
            padded
        }
    }
}

struct TradeDetailSectionHeader: View {
    let title: String

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .foregroundStyle(colorScheme == .light ? colors.tertiaryText : colors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.35)
            .padding(.bottom, colorScheme == .light ? ExperienceSpacing.xxs : 0)
    }
}

// MARK: - Quick stats

struct TradeDetailQuickStatsContent: View {
    let trade: Trade

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var pnlTone: Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
        )
    }

    private var quickStatsRowSpacing: CGFloat {
        colorScheme == .light ? ExperienceSpacing.sm : TradeDetailLayout.groupSpacing
    }

    var body: some View {
        VStack(spacing: quickStatsRowSpacing) {
                TradeDetailCompactStatRow(centered: true, cells: {
                    var cells: [TradeDetailStatCell] = [
                        TradeDetailStatCell(
                            label: "P&L",
                            value: TradeDisplay.pnlText(trade.realizedPnL),
                            valueColor: pnlTone
                        ),
                        TradeDetailStatCell(
                            label: "Targeted R:R",
                            value: TradeDisplay.compactRRText(trade.riskReward) ?? "–"
                        ),
                    ]
                    if let maxRr = TradeDisplay.compactRRText(trade.maxRrReached) {
                        cells.append(
                            TradeDetailStatCell(label: "Max R:R", value: maxRr)
                        )
                    }
                    cells.append(
                        TradeDetailStatCell(
                            label: "Contracts",
                            value: TradeDisplay.contractsText(for: trade.quantity)
                        )
                    )
                    return cells
                }())

                TradeDetailStatDivider()

                TradeDetailCompactStatRow(centered: true, cells: {
                    var cells: [TradeDetailStatCell] = [
                        TradeDetailStatCell(
                            label: "Points Targeted",
                            value: TradeDisplay.pointsText(trade.points) ?? "–"
                        ),
                        TradeDetailStatCell(
                            label: "Actual Points",
                            value: TradeDisplay.pointsText(TradePointsAndRealizedRr.computeActualPoints(trade: trade)) ?? "–"
                        ),
                        TradeDetailStatCell(
                            label: "Realized R:R",
                            value: TradeDisplay.compactRRText(TradePointsAndRealizedRr.resolveRealizedRr(trade: trade)) ?? "–"
                        ),
                    ]
                    if let risk = trade.dollarRisk, risk > 0 {
                        cells.append(
                            TradeDetailStatCell(
                                label: "Planned Risk",
                                value: TradeDisplay.priceText(risk)
                            )
                        )
                    }
                    return cells
                }())

                TradeDetailStatDivider()

                TradeDetailCompactStatRow(centered: true, cells: [
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
                        label: "Duration",
                        value: TradeDisplay.holdDuration(for: trade) ?? "–"
                    ),
                ])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TradeDetailQuickStatsSection: View {
    let trade: Trade

    var body: some View {
        TradeDetailGroupedSurface {
            TradeDetailQuickStatsContent(trade: trade)
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
    var centered: Bool = false
    let cells: [TradeDetailStatCell]

    @Environment(\.themeColors) private var colors

    private var columnAlignment: HorizontalAlignment {
        centered ? .center : .leading
    }

    private var frameAlignment: Alignment {
        centered ? .center : .leading
    }

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.xs) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: columnAlignment, spacing: 2) {
                    Text(cell.label)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .multilineTextAlignment(centered ? .center : .leading)
                    Text(cell.value)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(cell.valueColor ?? colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(centered ? .center : .leading)
                    if let subtitle = cell.subtitle {
                        Text(subtitle)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(centered ? .center : .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
    }
}

private struct TradeDetailStatDivider: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colors.separator.opacity(colorScheme == .light ? 1 : 0.6))
            .frame(height: ExperienceBorder.hairline)
    }
}

// MARK: - Comparison

struct TradeDetailComparisonSection: View {
    let trade: Trade
    let bundle: TradeDetailAnalytics.CohortBundle
    let filterContext: TradeDetailAnalytics.ComparisonFilterContext
    var quickInsight: TradeDetailAnalytics.QuickInsight?

    @State private var selectedFilter: TradeDetailAnalytics.ComparisonFilter = .all
    @State private var didApplyInitialFilter = false

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    /// Only the cohort for the active filter — never substitute another filter's statistics.
    private var displayedCohort: TradeDetailAnalytics.CohortComparison? {
        bundle.cohort(for: selectedFilter)
    }

    private var initialFilter: TradeDetailAnalytics.ComparisonFilter {
        if bundle.cohort(for: .all) != nil { return .all }
        for filter in TradeDetailAnalytics.ComparisonFilter.allCases where bundle.cohort(for: filter) != nil {
            return filter
        }
        return .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
            TradeDetailSectionHeader(title: "Compared to Your Trades")

            TradeDetailGroupedSurface {
                VStack(spacing: TradeDetailLayout.groupSpacing) {
                    comparisonFilterRow

                    if let cohort = displayedCohort {
                        Text("\(cohort.tradeCount) prior trades in this cohort")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        comparisonHeaderRow

                        comparisonRow(
                            label: "P&L",
                            thisValue: TradeDisplay.pnlText(trade.realizedPnL),
                            avgValue: TradeDisplay.pnlText(Money(amount: cohort.avgPnL)),
                            thisTone: theme.metricColor(
                                for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                            )
                        )

                        if let winRate = cohort.winRate {
                            comparisonRow(
                                label: "Win Rate",
                                thisValue: tradeOutcomeWinText,
                                avgValue: NumberDisplay.percent(
                                    NSDecimalNumber(decimal: winRate * 100).doubleValue,
                                    minimumFractionDigits: 0,
                                    maximumFractionDigits: 0
                                )
                            )
                        }

                        if let tradeRR = TradeDetailAnalytics.resolvedTargetRR(for: trade),
                           let avgTarget = cohort.avgTargetRR
                        {
                            comparisonRow(
                                label: "Target R:R",
                                thisValue: TradeDisplay.compactRRText(tradeRR) ?? "–",
                                avgValue: TradeDisplay.compactRRText(avgTarget) ?? "–"
                            )
                        }

                        if let tradeRealized = TradeDetailAnalytics.resolvedRealizedRR(for: trade),
                           let avgRealized = cohort.avgRealizedRR
                        {
                            comparisonRow(
                                label: "Realized R:R",
                                thisValue: TradeDisplay.compactRRText(tradeRealized) ?? "–",
                                avgValue: TradeDisplay.compactRRText(avgRealized) ?? "–"
                            )
                        }

                        if let tradeHold = TradeDetailAnalytics.holdSeconds(for: trade),
                           let avgHold = cohort.avgHoldSeconds
                        {
                            comparisonRow(
                                label: "Hold",
                                thisValue: TradeDisplay.compactHoldDuration(seconds: tradeHold) ?? "–",
                                avgValue: TradeDisplay.compactHoldDuration(seconds: avgHold) ?? "–"
                            )
                        }

                        if let percentileLine = percentileSummary(for: cohort) {
                            Text(percentileLine)
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let insightText = primaryInsight(for: cohort) {
                            Text(insightText)
                                .experienceStyle(.caption2, color: colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(comparisonEmptyMessage)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear {
            guard !didApplyInitialFilter else { return }
            didApplyInitialFilter = true
            selectedFilter = initialFilter
        }
        .accessibilityIdentifier("detail.trade.comparison")
    }

    private var comparisonEmptyMessage: String {
        guard filterContext.isAvailable(selectedFilter) else {
            return "This filter isn't available for this trade."
        }
        return "Not enough similar trades in this filter yet (need at least \(TradeDetailAnalytics.minCohortTrades))."
    }

    private var comparisonFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(TradeDetailAnalytics.ComparisonFilter.allCases) { filter in
                    ExperienceChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter,
                        compact: true
                    ) {
                        selectedFilter = filter
                    }
                    .disabled(!filterContext.isAvailable(filter))
                    .opacity(filterContext.isAvailable(filter) ? 1 : 0.45)
                }
            }
        }
    }

    private var tradeOutcomeWinText: String {
        guard let pnl = trade.realizedPnL?.amount else { return "–" }
        if pnl > 0 { return "Win" }
        if pnl < 0 { return "Loss" }
        return "Flat"
    }

    private func percentileSummary(for cohort: TradeDetailAnalytics.CohortComparison) -> String? {
        var parts: [String] = []
        if let percentile = cohort.pnlPercentile {
            parts.append(
                "P&L \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) percentile"
            )
        }
        if let percentile = cohort.targetRRPercentile, TradeDetailAnalytics.resolvedTargetRR(for: trade) != nil {
            parts.append(
                "Target R:R \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) percentile"
            )
        }
        if let percentile = cohort.realizedRRPercentile, TradeDetailAnalytics.resolvedRealizedRR(for: trade) != nil {
            parts.append(
                "Realized R:R \(NumberDisplay.percent(percentile, minimumFractionDigits: 0, maximumFractionDigits: 0)) percentile"
            )
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
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

    private func primaryInsight(for cohort: TradeDetailAnalytics.CohortComparison) -> String? {
        if selectedFilter == .all, let quickInsight {
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

                    if let sideLine = sideComparisonLine {
                        Text(sideLine)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let sessionLine = sessionComparisonLine {
                        Text(sessionLine)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let windowLine = rollingWindowLine {
                        Text(windowLine)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(history.comparisonSentence)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("detail.trade.tickerHistory")
    }

    private var sideComparisonLine: String? {
        guard let long = history.long, let short = history.short, long.tradeCount >= 1, short.tradeCount >= 1 else {
            return nil
        }
        var parts: [String] = []
        if let longWin = long.winRate {
            parts.append(
                "Long \(NumberDisplay.percent(NSDecimalNumber(decimal: longWin * 100).doubleValue, minimumFractionDigits: 0, maximumFractionDigits: 0)) · \(long.tradeCount) trades"
            )
        }
        if let shortWin = short.winRate {
            parts.append(
                "Short \(NumberDisplay.percent(NSDecimalNumber(decimal: shortWin * 100).doubleValue, minimumFractionDigits: 0, maximumFractionDigits: 0)) · \(short.tradeCount) trades"
            )
        }
        guard parts.count == 2 else { return nil }
        return parts.joined(separator: " · ")
    }

    private var sessionComparisonLine: String? {
        let slices = history.sessions.filter { $0.tradeCount >= 2 }.prefix(3)
        guard !slices.isEmpty else { return nil }
        return slices.map { slice in
            let win = slice.winRate.map {
                NumberDisplay.percent(NSDecimalNumber(decimal: $0 * 100).doubleValue, minimumFractionDigits: 0, maximumFractionDigits: 0)
            } ?? "–"
            return "\(slice.session) \(win) WR (\(NumberDisplay.integer(slice.tradeCount)))"
        }
        .joined(separator: " · ")
    }

    private var rollingWindowLine: String? {
        let windows = [("30d", history.window30d), ("90d", history.window90d)]
            .compactMap { label, window -> String? in
                guard let window, window.tradeCount >= 1 else { return nil }
                let pnl = TradeDisplay.pnlText(Money(amount: window.totalPnL))
                let win = window.winRate.map {
                    NumberDisplay.percent(NSDecimalNumber(decimal: $0 * 100).doubleValue, minimumFractionDigits: 0, maximumFractionDigits: 0)
                } ?? "–"
                return "Last \(label): \(NumberDisplay.integer(window.tradeCount)) trades · \(win) WR · \(pnl)"
            }
        guard !windows.isEmpty else { return nil }
        return windows.joined(separator: " · ")
    }

    private var summaryMetricsLine: String {
        var parts: [String] = ["\(NumberDisplay.integer(history.previousTradeCount)) Previous Trades"]
        if let winRate = history.winRate {
            parts.append("\(NumberDisplay.percent(NSDecimalNumber(decimal: winRate * 100).doubleValue, minimumFractionDigits: 0, maximumFractionDigits: 0)) Win")
        }
        if let profitFactor = history.profitFactor {
            parts.append("\(NumberDisplay.decimal(profitFactor, minimumFractionDigits: 1, maximumFractionDigits: 1)) PF")
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
        if setupRows.isEmpty,
           executionPsychologyRows.isEmpty,
           noteBodies.isEmpty
        {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: TradeDetailLayout.journalBlockSpacing) {
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

                if !setupRows.isEmpty {
                    TradeDetailJournalFieldGroup(title: "Setup", rows: setupRows)
                }
                if !executionPsychologyRows.isEmpty {
                    TradeDetailJournalFieldGroup(title: "Execution & Psychology", rows: executionPsychologyRows)
                }
            }
            .accessibilityIdentifier("detail.trade.journal")
        }
    }

    private var noteBodies: [String] {
        if isOwner {
            return notes
                .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let caption = trade.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            return [caption]
        }
        return []
    }

    private var setupRows: [(String, String)] {
        guard isOwner else { return [] }
        var rows: [(String, String)] = []
        if let session = trade.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            rows.append(("Session", session))
        }
        if let timeframe = trade.timeframe?.trimmingCharacters(in: .whitespacesAndNewlines), !timeframe.isEmpty {
            rows.append(("Timeframe", timeframe))
        }
        if let market = trade.marketCondition?.trimmingCharacters(in: .whitespacesAndNewlines), !market.isEmpty {
            rows.append(("Market Condition", market))
        }
        if trade.newsEvent == true {
            rows.append(("News Event", "Yes"))
        }
        return rows
    }

    private var executionPsychologyRows: [(String, String)] {
        guard isOwner else { return [] }
        var rows: [(String, String)] = []
        if let followed = trade.followedPlan {
            rows.append(("Followed Plan", followed ? "Yes" : "No"))
        }
        if let confidence = trade.confidence {
            rows.append(("Conviction", "\(confidence)/5"))
        }
        if let rating = trade.executionRating {
            rows.append(("Execution Rating", "\(rating)/5"))
        }
        if let emotion = trade.emotion?.trimmingCharacters(in: .whitespacesAndNewlines), !emotion.isEmpty {
            rows.append(("Emotion Before", emotion))
        }
        if let exitEmotion = trade.exitEmotion?.trimmingCharacters(in: .whitespacesAndNewlines), !exitEmotion.isEmpty {
            rows.append(("Emotion After", exitEmotion))
        }
        if let psych = trade.psychologyNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !psych.isEmpty {
            rows.append(("Psychology Notes", psych))
        }
        return rows
    }

}

private struct TradeDetailJournalFieldGroup: View {
    let title: String
    let rows: [(String, String)]

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    private var labelWidth: CGFloat {
        colorScheme == .light ? 116 : 88
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TradeDetailLayout.groupSpacing) {
            TradeDetailSectionHeader(title: title)
            TradeDetailGroupedSurface {
                VStack(spacing: colorScheme == .light ? ExperienceSpacing.xs : 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                            Text(row.0)
                                .font(
                                    .system(
                                        .caption,
                                        design: .default,
                                        weight: colorScheme == .light ? .medium : .regular
                                    )
                                )
                                .foregroundStyle(colors.tertiaryText)
                                .multilineTextAlignment(.leading)
                                .frame(width: labelWidth, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(row.1)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, TradeDetailLayout.detailRowVerticalPadding(colorScheme: colorScheme))
                        if index < rows.count - 1 {
                            TradeDetailStatDivider()
                        }
                    }
                }
            }
        }
    }
}
