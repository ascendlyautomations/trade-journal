import SwiftUI

/// Compact shared-trade preview for DMs, Trade Rooms, and Comments.
enum SharedTradePreviewMetrics {
    static let maxCardWidth: CGFloat = 240
    static let screenshotMaxHeight: CGFloat = 120
    static let composerThumbnailSide: CGFloat = 44
    static let composerRowMaxHeight: CGFloat = 52
}

enum SharedTradePreviewStyle: Equatable {
    /// Vertical card — thread bubbles and comment rows.
    case card(isOutgoing: Bool)
    /// Horizontal strip — comment composer staging row.
    case composerStrip
}

struct SharedTradePreviewCard: View {
    let trade: Trade?
    let tradeID: TradeID
    let imagePipeline: any ImagePipeline
    var style: SharedTradePreviewStyle = .card(isOutgoing: false)
    var loadFailed: Bool = false
    var mediaLayoutWidth: CGFloat? = nil
    var accountProviderName: String? = nil
    /// Livestream chat trade cards — aspect-fit hero; default aspect-fill for DMs/comments.
    var screenshotUsesAspectFit: Bool = false

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var resolvedWidth: CGFloat {
        mediaLayoutWidth ?? SharedTradePreviewMetrics.maxCardWidth
    }

    var body: some View {
        Group {
            switch style {
            case .card(let isOutgoing):
                cardBody(isOutgoing: isOutgoing)
            case .composerStrip:
                composerStripBody
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens trade detail")
    }

    // MARK: - Card

    @ViewBuilder
    private func cardBody(isOutgoing: Bool) -> some View {
        if let trade {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                sharedTradeLabel(isOutgoing: isOutgoing)

                if ProfileCardMediaPresence.tradeMedia(in: trade) != nil {
                    tradeScreenshotPreview(for: trade)
                }

                headlineRow(trade, isOutgoing: isOutgoing)
                metaChips(trade, isOutgoing: isOutgoing)
            }
            .frame(maxWidth: resolvedWidth, alignment: .leading)
        } else if loadFailed {
            loadingOrFailedBody(isOutgoing: isOutgoing, failed: true)
        } else {
            loadingOrFailedBody(isOutgoing: isOutgoing, failed: false)
        }
    }

  @ViewBuilder
    private func loadingOrFailedBody(isOutgoing: Bool, failed: Bool) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            sharedTradeLabel(isOutgoing: isOutgoing)
            if failed {
                Text("Trade unavailable")
                    .experienceStyle(.caption, color: isOutgoing ? colors.onAccent.opacity(0.88) : colors.error)
            } else {
                SharedContentMessageCardLoadingPlaceholder(
                    label: "Loading trade…",
                    isOutgoing: isOutgoing,
                    mediaLayoutWidth: resolvedWidth
                )
            }
        }
        .frame(maxWidth: resolvedWidth, alignment: .leading)
    }

    // MARK: - Composer strip

    private var composerStripBody: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            if let trade, ProfileCardMediaPresence.tradeMedia(in: trade) != nil {
                TradePreviewThumbnail(
                    trade: trade,
                    imagePipeline: imagePipeline,
                    size: .compact
                )
                .frame(
                    width: SharedTradePreviewMetrics.composerThumbnailSide,
                    height: SharedTradePreviewMetrics.composerThumbnailSide
                )
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.xs, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Attached trade")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
                if let trade {
                    Text("\(trade.symbol.ticker) · \(TradeDisplay.pnlText(trade.realizedPnL))")
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    ExperienceIndeterminateProgress()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(maxHeight: SharedTradePreviewMetrics.composerRowMaxHeight)
        .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    @ViewBuilder
    private func tradeScreenshotPreview(for trade: Trade) -> some View {
        let cornerRadius = RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
        if screenshotUsesAspectFit {
            TradePreviewThumbnail(
                trade: trade,
                imagePipeline: imagePipeline,
                size: .messageHero(maxHeight: SharedTradePreviewMetrics.screenshotMaxHeight),
                layoutWidth: resolvedWidth
            )
            .frame(maxWidth: resolvedWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(cornerRadius)
        } else {
            TradePreviewThumbnail(
                trade: trade,
                imagePipeline: imagePipeline,
                size: .sharedPreviewHero(maxHeight: SharedTradePreviewMetrics.screenshotMaxHeight),
                layoutWidth: resolvedWidth
            )
            .frame(maxWidth: resolvedWidth)
            .clipShape(cornerRadius)
        }
    }

    // MARK: - Shared chrome

    private func sharedTradeLabel(isOutgoing: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption2.weight(.semibold))
            Text("Shared trade")
                .experienceStyle(.caption2, color: labelColor(isOutgoing: isOutgoing))
        }
    }

    @ViewBuilder
    private func headlineRow(_ trade: Trade, isOutgoing: Bool) -> some View {
        if isOutgoing {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(trade.symbol.ticker)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.onAccent)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.onAccent)
                    .lineLimit(1)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(trade.symbol.ticker)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(pnlColor(for: trade.realizedPnL))
                    .lineLimit(1)
            }
        }
    }

    private func metaChips(_ trade: Trade, isOutgoing: Bool) -> some View {
        FlowLayout(spacing: 4) {
            chip(TradeDisplay.sideTitle(trade.side), isOutgoing: isOutgoing, emphasized: true)
            if let mode = accountModeLabel(for: trade) {
                chip(mode, isOutgoing: isOutgoing)
            }
            if trade.riskReward != nil {
                chip(TradeDisplay.rrText(trade.riskReward), isOutgoing: isOutgoing)
            }
            chip(TradeDisplay.quantityBadgeText(trade.quantity), isOutgoing: isOutgoing)
        }
    }

    private func chip(_ title: String, isOutgoing: Bool, emphasized: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(chipTextColor(isOutgoing: isOutgoing, emphasized: emphasized))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(chipBackground(isOutgoing: isOutgoing, emphasized: emphasized), in: Capsule())
    }

    private func accountModeLabel(for trade: Trade) -> String? {
        if trade.mode == .copyTraded {
            return TradeDisplay.tradeModeFallbackTitle(.copyTraded)
        }
        if let caption = TradeDisplay.publicPostedAccountCaption(
            providerName: accountProviderName,
            accountMode: trade.accountMode,
            publicAccountBadge: trade.publicAccountBadge
        ) {
            return caption
        }
        return TradeDisplay.tradeModeFallbackTitle(trade.mode)
    }

    private func labelColor(isOutgoing: Bool) -> Color {
        isOutgoing ? colors.onAccent.opacity(0.78) : colors.tertiaryText
    }

    private func chipTextColor(isOutgoing: Bool, emphasized: Bool) -> Color {
        if isOutgoing {
            return colors.onAccent.opacity(emphasized ? 0.95 : 0.82)
        }
        return emphasized ? colors.primaryText : colors.secondaryText
    }

    private func chipBackground(isOutgoing: Bool, emphasized: Bool) -> Color {
        if isOutgoing {
            return colors.onAccent.opacity(emphasized ? 0.14 : 0.08)
        }
        return emphasized ? colors.accentMuted : colors.fillTertiary
    }

    private func pnlColor(for money: Money?) -> Color {
        guard let amount = money?.amount else { return colors.secondaryText }
        return theme.metricColor(for: NSDecimalNumber(decimal: amount).doubleValue)
    }

    private var accessibilityLabel: String {
        if loadFailed, trade == nil { return "Shared trade unavailable" }
        guard let trade else { return "Shared trade loading" }
        var parts = [
            "Shared trade",
            trade.symbol.ticker,
            TradeDisplay.pnlText(trade.realizedPnL),
            TradeDisplay.sideTitle(trade.side),
        ]
        if let mode = accountModeLabel(for: trade) {
            parts.append(mode)
        }
        return parts.joined(separator: ", ")
    }
}

/// Simple horizontal chip wrapping for compact meta rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? SharedTradePreviewMetrics.maxCardWidth
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}