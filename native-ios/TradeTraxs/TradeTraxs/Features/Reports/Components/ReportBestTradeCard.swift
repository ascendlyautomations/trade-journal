import SwiftUI

/// Tappable Best Trade reference — never shows raw trade IDs.
struct ReportBestTradeCard: View {
    enum Presentation: Equatable {
        case loading
        case available(Trade)
        case unavailable
    }

    let presentation: Presentation
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.xs) {
                ExperienceIcon(icon: .trophy, size: .sm, color: colors.accent)
                Text("Best Trade")
                    .experienceStyle(.headline, color: colors.accent)
            }

            switch presentation {
            case .loading:
                ExperienceSkeleton(height: 44, cornerRadius: ExperienceRadius.sm)
                    .accessibilityLabel("Loading best trade")

            case .unavailable:
                Text("Trade unavailable")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ExperienceSpacing.md)
                    .background(colors.fillSecondary.opacity(0.55), in: RoundedRectangle(
                        cornerRadius: ExperienceRadius.md,
                        style: .continuous
                    ))
                    .accessibilityIdentifier("reports.detail.bestTrade.unavailable")

            case .available(let trade):
                Button(action: onOpen) {
                    HStack(spacing: ExperienceSpacing.sm) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summaryLine(for: trade))
                                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                                .foregroundStyle(pnlColor(for: trade))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Text(TradeDisplay.sideTitle(trade.side))
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
                    }
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.backgroundSecondary.opacity(0.7), in: RoundedRectangle(
                        cornerRadius: ExperienceRadius.md,
                        style: .continuous
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                            .stroke(colors.border.opacity(0.5), lineWidth: ExperienceBorder.thin)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: trade))
                .accessibilityHint("Opens trade detail")
                .accessibilityIdentifier("reports.detail.bestTrade.open")
            }
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(colors.fillSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                        .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.thin)
                }
        }
        .accessibilityIdentifier("reports.detail.section.best trade")
    }

    /// `+$542.75 • NQ • Aug 12`
    private func summaryLine(for trade: Trade) -> String {
        let pnl = TradeDisplay.pnlText(trade.realizedPnL)
        let symbol = trade.symbol.ticker
        let date = Self.shortDay.string(from: trade.exitAt ?? trade.entryAt)
        return "\(pnl) • \(symbol) • \(date)"
    }

    private func pnlColor(for trade: Trade) -> Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
        )
    }

    private func accessibilityLabel(for trade: Trade) -> String {
        "Best trade, \(summaryLine(for: trade))"
    }

    private static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()
}
