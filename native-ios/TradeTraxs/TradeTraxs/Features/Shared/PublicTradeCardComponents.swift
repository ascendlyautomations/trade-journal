import SwiftUI

/// Ticker + P&L headline row for public trade cards — matched size, weight, and baseline.
struct PublicTradeHeadlineRow: View {
    let ticker: String
    let realizedPnL: Money?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            Text(ticker)
                .font(ExperienceTypography.headline)
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)

            Spacer(minLength: ExperienceSpacing.xs)

            Text(TradeDisplay.pnlText(realizedPnL))
                .font(ExperienceTypography.headline.monospacedDigit())
                .foregroundStyle(
                    theme.metricColor(
                        for: NSDecimalNumber(decimal: realizedPnL?.amount ?? 0).doubleValue
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Side, account-type, RR, quantity (and optional session) chips for public trade surfaces.
struct PublicTradeMetaChipRow: View {
    enum LayoutStyle: Sendable {
        /// Feed / detail — horizontal scroll when chips overflow.
        case horizontalScroll
        /// Profile compact cards — wrap onto additional lines within available width.
        case wrap
    }

    private let trade: Trade?
    private let summary: TradeSummary?
    private let showsQuantity: Bool
    private let showsSession: Bool
    private let layout: LayoutStyle
    /// Profile grouped copy line — replaces per-row account badge (`copyTradePublicModeSummary`).
    private let copyTradeGroupedModeSummary: String?

    init(
        trade: Trade,
        showsQuantity: Bool = true,
        showsSession: Bool = true,
        layout: LayoutStyle = .horizontalScroll
    ) {
        self.trade = trade
        self.summary = nil
        self.showsQuantity = showsQuantity
        self.showsSession = showsSession
        self.layout = layout
        self.copyTradeGroupedModeSummary = nil
    }

    init(
        summary: TradeSummary,
        showsQuantity: Bool = true,
        showsSession: Bool = true,
        layout: LayoutStyle = .horizontalScroll,
        copyTradeGroupedModeSummary: String? = nil
    ) {
        self.trade = nil
        self.summary = summary
        self.showsQuantity = showsQuantity
        self.showsSession = showsSession
        self.layout = layout
        self.copyTradeGroupedModeSummary = copyTradeGroupedModeSummary
    }

    var body: some View {
        switch layout {
        case .horizontalScroll:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PublicTradeMetaChipRowLayout.chipSpacing) {
                    chipContent
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        case .wrap:
            ExperienceFlowLayout(
                spacing: PublicTradeMetaChipRowLayout.chipSpacing,
                rowSpacing: PublicTradeMetaChipRowLayout.chipSpacing
            ) {
                chipContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        if let trade {
            PublicTradeMetaChip(
                title: TradeDisplay.sideTitle(trade.side),
                tone: trade.side == .long ? .success : .error
            )
            if trade.mode != .copyTraded, let accountBadge = trade.publicAccountBadge {
                PublicTradeMetaChip(title: accountBadge, tone: .info)
            }
            if trade.riskReward != nil {
                PublicTradeMetaChip(title: TradeDisplay.rrText(trade.riskReward), tone: .info)
            }
            if let points = TradeDisplay.pointsText(trade.points) {
                PublicTradeMetaChip(title: "Pts \(points)", tone: .info)
            }
            if trade.mode == .copyTraded {
                PublicTradeMetaChip(
                    title: TradeDisplay.tradeModeFallbackTitle(.copyTraded) ?? "Copy Traded",
                    tone: .info
                )
            }
            if showsQuantity {
                PublicTradeMetaChip(
                    title: TradeDisplay.quantityBadgeText(trade.quantity),
                    tone: .info
                )
            }
            if let duration = TradeDisplay.cardDurationText(for: trade) {
                PublicTradeMetaChip(title: duration, tone: .info)
            }
            if showsSession,
               let session = trade.sessionLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !session.isEmpty
            {
                PublicTradeMetaChip(title: session, tone: .info)
            }
        } else if let summary {
            PublicTradeMetaChip(
                title: TradeDisplay.sideTitle(summary.side),
                tone: summary.side == .long ? .success : .error
            )
            if summary.mode == .copyTraded,
               let line = copyTradeGroupedModeSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty
            {
                PublicTradeCopyGroupModeLine(text: line)
            } else if summary.mode != .copyTraded, let accountBadge = summary.publicAccountBadge {
                PublicTradeMetaChip(title: accountBadge, tone: .info)
            }
            if summary.riskReward != nil {
                PublicTradeMetaChip(title: TradeDisplay.rrText(summary.riskReward), tone: .info)
            }
            if let points = TradeDisplay.pointsText(summary.points) {
                PublicTradeMetaChip(title: "Pts \(points)", tone: .info)
            }
            if showsQuantity {
                PublicTradeMetaChip(
                    title: TradeDisplay.quantityBadgeText(summary.quantity),
                    tone: .info
                )
            }
            if let duration = TradeDisplay.cardDurationText(for: summary) {
                PublicTradeMetaChip(title: duration, tone: .info)
            }
        }
    }
}

/// Capsule chip insets for trade metadata (MNQ, Long, RR, qty, etc.).
nonisolated enum TradeMetaChipMetrics {
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 3
    static let spacing: CGFloat = 3
}

private enum PublicTradeMetaChipRowLayout {
    static let chipSpacing = TradeMetaChipMetrics.spacing
    static let chipHorizontalPadding = TradeMetaChipMetrics.horizontalPadding
    static let chipVerticalPadding = TradeMetaChipMetrics.verticalPadding
}

/// Full-width grouped copy-account line in the meta chip row (Profile card interior).
struct PublicTradeCopyGroupModeLine: View {
    let text: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(text)
            .experienceStyle(.caption, color: colors.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("profile.trade.copyModeSummaryInCard")
    }
}

// MARK: - Execution metrics (Profile + social Trade Detail)

nonisolated enum TradeExecutionMetricsPriceDisplay: Sendable {
    case fullPrecision
    case profileCardRounded
}

/// Two-row execution block — R:R / Contracts / Duration, then Entry / Exit / Points (times under prices).
struct TradeExecutionMetricsTwoRowGrid: View {
    private let riskReward: Decimal?
    private let quantity: Decimal
    private let durationText: String?
    private let entryPrice: Decimal?
    private let exitPrice: Decimal?
    private let points: Decimal?
    private let entryAt: Date
    private let exitAt: Date?
    private let priceDisplay: TradeExecutionMetricsPriceDisplay

    init(trade: Trade) {
        riskReward = trade.riskReward
        quantity = trade.quantity
        durationText = TradeDisplay.holdDuration(for: trade)
        entryPrice = trade.entryPrice
        exitPrice = trade.exitPrice
        points = trade.points
        entryAt = trade.entryAt
        exitAt = trade.exitAt
        priceDisplay = .fullPrecision
    }

    init(
        summary: TradeSummary,
        priceDisplay: TradeExecutionMetricsPriceDisplay = .fullPrecision
    ) {
        riskReward = summary.riskReward
        quantity = summary.quantity
        durationText = TradeDisplay.cardDurationText(for: summary)
        entryPrice = summary.entryPrice
        exitPrice = summary.exitPrice
        points = summary.points
        entryAt = summary.entryAt
        exitAt = summary.exitAt
        self.priceDisplay = priceDisplay
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: TradeExecutionMetricsLayout.rowSpacing) {
            metricsRow(
                TradeExecutionMetricsCell(
                    label: "R:R",
                    value: TradeDisplay.compactRRText(riskReward) ?? "—"
                ),
                TradeExecutionMetricsCell(
                    label: "Contracts",
                    value: TradeDisplay.contractsText(for: quantity)
                ),
                TradeExecutionMetricsCell(
                    label: "Duration",
                    value: durationText ?? "—"
                )
            )
            HStack(alignment: .top, spacing: ExperienceSpacing.xxs) {
                TradeExecutionEntryExitColumn(
                    label: "Entry",
                    price: TradeDisplay.executionPriceText(entryPrice, display: priceDisplay),
                    time: TradeDisplay.entryExecutionTimeText(entryAt: entryAt, exitAt: exitAt)
                )
                TradeExecutionEntryExitColumn(
                    label: "Exit",
                    price: TradeDisplay.executionPriceText(exitPrice, display: priceDisplay),
                    time: TradeDisplay.exitExecutionTimeText(entryAt: entryAt, exitAt: exitAt)
                )
                TradeExecutionMetricsCell(
                    label: "Points",
                    value: TradeDisplay.pointsText(points) ?? "—"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricsRow(_ cells: TradeExecutionMetricsCell...) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.xxs) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                cell
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private enum TradeExecutionMetricsLayout {
    static let rowSpacing = ExperienceSpacing.xs
}

private struct TradeExecutionMetricsCell: View {
    let label: String
    let value: String
    var subtitle: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(1)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let subtitle {
                Text(subtitle)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Entry / Exit column — one shared price + time style so columns cannot diverge.
private struct TradeExecutionEntryExitColumn: View {
    let label: String
    let price: String
    let time: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: TradeExecutionEntryExitTypography.stackSpacing) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(1)
            TradeExecutionEntryExitTypography.priceText(price, colors: colors)
            TradeExecutionEntryExitTypography.timeText(time, colors: colors)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }
}

private enum TradeExecutionEntryExitTypography {
    static let stackSpacing: CGFloat = 2
    static let priceMinimumScale: CGFloat = 0.75
    static let timeMinimumScale: CGFloat = 0.75

    @ViewBuilder
    static func priceText(_ text: String, colors: SemanticColorPalette) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
            .foregroundStyle(colors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(priceMinimumScale)
            .allowsTightening(true)
            .layoutPriority(1)
    }

    @ViewBuilder
    static func timeText(_ text: String, colors: SemanticColorPalette) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.regular).monospacedDigit())
            .foregroundStyle(colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(timeMinimumScale)
            .allowsTightening(true)
            .layoutPriority(1)
    }
}

/// Compact intrinsic-width chip for public trade metadata rows.
private struct PublicTradeMetaChip: View {
    let title: String
    var tone: BannerTone = .info

    @Environment(\.themeColors) private var colors

    var body: some View {
        let toneColor = tone.color(in: colors)
        Text(title)
            .experienceStyle(.caption2, color: toneColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, PublicTradeMetaChipRowLayout.chipHorizontalPadding)
            .padding(.vertical, PublicTradeMetaChipRowLayout.chipVerticalPadding)
            .background(toneColor.opacity(ExperienceOpacity.subtle))
            .clipShape(Capsule())
            .experienceAccessibility(label: title, identifier: "tag.\(title)")
    }
}
