import SwiftUI

/// Compact linked-trade block for full-screen Clips overlays and clip detail.
struct ClipLinkedTradeSection: View {
    enum Style: Equatable {
        case clipsOverlay
        case detailBody
    }

    let trade: Trade
    var style: Style = .clipsOverlay
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private static let descriptionLineLimit = 3

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                Text("Linked Trade")
                    .font(sectionLabelFont)
                    .foregroundStyle(sectionLabelColor)
                    .shadow(color: overlayShadowColor, radius: 2, y: 1)

                Text(summaryLine)
                    .font(summaryFont)
                    .foregroundStyle(summaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .shadow(color: overlayShadowColor, radius: 2, y: 1)

                if let dateText {
                    Text(dateText)
                        .font(metaFont)
                        .foregroundStyle(metaColor)
                        .lineLimit(1)
                        .shadow(color: overlayShadowColor, radius: 2, y: 1)
                }

                if let description = Self.descriptionText(for: trade) {
                    Text(description)
                        .font(descriptionFont)
                        .foregroundStyle(descriptionColor)
                        .lineLimit(Self.descriptionLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shadow(color: overlayShadowColor, radius: 2, y: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("clips.linked.trade.\(trade.id.rawValue)")
    }

    /// Authoritative public trade description — same field as Trade Detail.
    static func descriptionText(for trade: Trade) -> String? {
        let trimmed = trade.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var summaryLine: String {
        var parts = [
            TradeDisplay.pnlText(trade.realizedPnL),
            trade.symbol.ticker,
        ]
        let side = TradeDisplay.sideTitle(trade.side)
        if !side.isEmpty {
            parts.append(side)
        }
        return parts.joined(separator: " · ")
    }

    private var dateText: String? {
        TradeDisplay.dateText(trade.entryAt)
    }

    private var accessibilityLabel: String {
        var parts = ["Linked trade", trade.symbol.ticker, TradeDisplay.pnlText(trade.realizedPnL)]
        if let description = Self.descriptionText(for: trade) {
            parts.append(description)
        }
        return parts.joined(separator: ", ")
    }

    private var contentSpacing: CGFloat {
        switch style {
        case .clipsOverlay: return 4
        case .detailBody: return ExperienceSpacing.xxs
        }
    }

    private var sectionLabelFont: Font {
        switch style {
        case .clipsOverlay: return .caption2.weight(.semibold)
        case .detailBody: return .caption.weight(.semibold)
        }
    }

    private var summaryFont: Font {
        switch style {
        case .clipsOverlay: return .caption.weight(.semibold)
        case .detailBody: return .subheadline.weight(.semibold)
        }
    }

    private var metaFont: Font {
        switch style {
        case .clipsOverlay: return .caption2
        case .detailBody: return .caption
        }
    }

    private var descriptionFont: Font {
        switch style {
        case .clipsOverlay: return .caption
        case .detailBody: return .subheadline
        }
    }

    private var sectionLabelColor: Color {
        switch style {
        case .clipsOverlay: return .white.opacity(0.78)
        case .detailBody: return colors.secondaryText
        }
    }

    private var summaryColor: Color {
        switch style {
        case .clipsOverlay:
            return theme.metricColor(
                for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
            )
        case .detailBody:
            return theme.metricColor(
                for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
            )
        }
    }

    private var metaColor: Color {
        switch style {
        case .clipsOverlay: return .white.opacity(0.82)
        case .detailBody: return colors.tertiaryText
        }
    }

    private var descriptionColor: Color {
        switch style {
        case .clipsOverlay: return .white.opacity(0.9)
        case .detailBody: return colors.primaryText
        }
    }

    private var overlayShadowColor: Color {
        switch style {
        case .clipsOverlay: return .black.opacity(0.35)
        case .detailBody: return .clear
        }
    }
}
