import SwiftUI

/// Owner-journal trade card for the Trades history page.
///
/// Distinct from ``ProfileTradeCard`` — no likes/comments/share chrome.
/// Adapts layout when a screenshot is present vs absent.
struct TradeJournalCard: View {
    let trade: Trade
    let accountName: String?
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var hasImage: Bool {
        guard let thumbnail = trade.thumbnail else { return false }
        return !thumbnail.id.isEmpty
    }

    private var notes: String? {
        guard let note = trade.notePreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty
        else { return nil }
        return note
    }

    private var strategy: String? {
        guard let value = trade.strategy?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    var body: some View {
        Button(action: onOpen) {
            ExperienceCard {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    header
                    metaLine

                    if hasImage {
                        screenshot
                    } else {
                        executionGrid
                    }

                    performanceRow

                    if let strategy {
                        strategyBlock(strategy)
                    }

                    if let notes {
                        notesBlock(notes, lines: hasImage ? 3 : 4)
                    }

                    if !hasImage {
                        HStack {
                            Spacer(minLength: 0)
                            visibilityLabel
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens trade detail")
        .accessibilityIdentifier("trades.journalCard.\(trade.id.rawValue)")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.xs) {
                Text(trade.symbol.ticker)
                    .experienceStyle(.headline, color: colors.primaryText)
                Text("·")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                Text(TradeDisplay.sideTitle(trade.side).uppercased())
                    .experienceStyle(
                        .caption,
                        color: trade.side == .long ? colors.profit : colors.loss
                    )
                    .fontWeight(.semibold)
            }
            Spacer(minLength: ExperienceSpacing.xs)
            Text(TradeDisplay.pnlText(trade.realizedPnL))
                .experienceStyle(
                    .metric,
                    color: theme.metricColor(
                        for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                    )
                )
                .accessibilityLabel("P and L \(TradeDisplay.pnlText(trade.realizedPnL))")
            if hasImage {
                visibilityLabel
            }
        }
    }

    private var metaLine: some View {
        Text(TradeDisplay.journalContextLine(accountName: accountName, at: trade.entryAt))
            .experienceStyle(.caption, color: colors.secondaryText)
            .lineLimit(1)
    }

    private var screenshot: some View {
        GeometryReader { geo in
            TradeImageView(
                reference: trade.thumbnail,
                imagePipeline: imagePipeline,
                contentMode: .fill,
                side: 132,
                width: geo.size.width,
                height: 132
            )
        }
        .frame(height: 132)
        .accessibilityHidden(true)
    }

    private var executionGrid: some View {
        let duration = TradeDisplay.durationText(entryAt: trade.entryAt, exitAt: trade.exitAt)
        return VStack(spacing: ExperienceSpacing.sm) {
            HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                metricCell(title: "Entry", value: TradeDisplay.priceText(trade.entryPrice))
                metricCell(title: "Exit", value: TradeDisplay.priceText(trade.exitPrice))
                metricCell(title: "Contracts", value: TradeDisplay.contractsText(trade.quantity))
            }
            HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                if let rr = TradeDisplay.journalRRText(trade.riskReward) {
                    metricCell(title: "R:R", value: rr)
                }
                if let points = TradeDisplay.pointsText(trade.points) {
                    metricCell(title: "Points", value: points)
                }
                if let duration {
                    metricCell(title: "Duration", value: duration)
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private var performanceRow: some View {
        let metrics = performanceMetrics
        if !metrics.isEmpty {
            HStack(spacing: ExperienceSpacing.md) {
                ForEach(metrics, id: \.label) { item in
                    HStack(spacing: 4) {
                        Text(item.label)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(item.value)
                            .experienceStyle(.caption, color: colors.primaryText)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                metrics.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
            )
        }
    }

    private var performanceMetrics: [(label: String, value: String)] {
        var items: [(String, String)] = []
        // With image: show compact RR / points / contracts (execution grid is hidden).
        // Without image: those already appear in the execution grid — avoid duplicate.
        if hasImage {
            if let rr = TradeDisplay.journalRRText(trade.riskReward) {
                items.append(("R:R", rr))
            }
            if let points = TradeDisplay.pointsText(trade.points) {
                items.append(("Points", points))
            }
            items.append(("Contracts", TradeDisplay.contractsText(trade.quantity)))
            if let duration = TradeDisplay.durationText(entryAt: trade.entryAt, exitAt: trade.exitAt) {
                items.append(("Dur", duration))
            }
        } else if trade.entryPrice == nil && trade.exitPrice == nil {
            // Sparse trade — still surface whatever performance we have once.
            if let rr = TradeDisplay.journalRRText(trade.riskReward) {
                items.append(("R:R", rr))
            }
            if let points = TradeDisplay.pointsText(trade.points) {
                items.append(("Points", points))
            }
            if trade.quantity > 0 {
                items.append(("Contracts", TradeDisplay.contractsText(trade.quantity)))
            }
        }
        return items
    }

    private func strategyBlock(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SETUP")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup \(value)")
    }

    private func notesBlock(_ value: String, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NOTES")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notes \(value)")
    }

    private var visibilityLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: visibilitySymbol)
                .font(.caption2)
            Text(visibilityTitle)
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .foregroundStyle(colors.tertiaryText)
        .accessibilityLabel(visibilityTitle)
    }

    private var visibilitySymbol: String {
        switch trade.visibility {
        case .public: return "globe"
        case .private: return "lock.fill"
        case .followersOnly: return "person.2.fill"
        }
    }

    private var visibilityTitle: String {
        switch trade.visibility {
        case .public: return "Public"
        case .private: return "Private"
        case .followersOnly: return "Followers"
        }
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text(value)
                .experienceStyle(.footnote, color: colors.primaryText)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var accessibilitySummary: String {
        var parts = [
            trade.symbol.ticker,
            TradeDisplay.sideTitle(trade.side),
            TradeDisplay.pnlText(trade.realizedPnL),
        ]
        if let accountName, !accountName.isEmpty {
            parts.append(accountName)
        }
        if let strategy {
            parts.append(strategy)
        }
        parts.append(visibilityTitle)
        return parts.joined(separator: ", ")
    }
}
