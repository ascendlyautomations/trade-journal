import SwiftUI

/// Rich trade-share card for DM and Trade Room bubbles (web trade message card).
struct SharedTradeMessageCard: View {
    let trade: Trade?
    let tradeID: TradeID
    let imagePipeline: any ImagePipeline
    var isOutgoing: Bool
    var includesBackground: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            if let trade {
                if ProfileCardMediaPresence.tradeMedia(in: trade) != nil {
                    TradePreviewThumbnail(
                        trade: trade,
                        imagePipeline: imagePipeline,
                        size: .messageHero()
                    )
                    .frame(maxWidth: .infinity)
                    .modifier(SharedTradeMediaBleedModifier(enabled: !includesBackground))
                }

                sharedTradeHeader
                sharedTradeHeadline(trade)
                sharedTradeMetaRow(trade)
                sharedTradePricesRow(trade)
                sharedTradeDateRow(trade)
                if let note = displayNote(for: trade) {
                    Text(note)
                        .experienceStyle(.caption, color: secondaryTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                sharedTradeHeader
                Text("Loading trade…")
                    .experienceStyle(.subheadline, color: secondaryTextColor)
            }
        }
        .padding(.horizontal, includesBackground ? ExperienceSpacing.sm + 2 : 0)
        .padding(.vertical, includesBackground ? ExperienceSpacing.sm : 0)
        .frame(maxWidth: 280, alignment: .leading)
        .background {
            if includesBackground {
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(isOutgoing ? colors.accent : colors.incomingMessageBubble)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens trade detail")
        .accessibilityIdentifier("conversation.bubble.trade")
    }

    private var secondaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText
    }

    private var tertiaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.78) : colors.tertiaryText
    }

    private var sharedTradeHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.semibold))
            Text("Shared trade")
                .experienceStyle(.caption, color: tertiaryTextColor)
        }
    }

    @ViewBuilder
    private func sharedTradeHeadline(_ trade: Trade) -> some View {
        if isOutgoing {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                Text(trade.symbol.ticker)
                    .font(ExperienceTypography.headline)
                    .foregroundStyle(colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                Spacer(minLength: ExperienceSpacing.xxs)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .font(ExperienceTypography.headline.monospacedDigit())
                    .foregroundStyle(colors.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        } else {
            PublicTradeHeadlineRow(
                ticker: trade.symbol.ticker,
                realizedPnL: trade.realizedPnL
            )
        }
    }

    private func sharedTradeMetaRow(_ trade: Trade) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xxs) {
                metaChip(TradeDisplay.sideTitle(trade.side), emphasized: true)
                if let mode = modeLabel(for: trade) {
                    metaChip(mode)
                }
                if trade.riskReward != nil {
                    metaChip(TradeDisplay.rrText(trade.riskReward))
                }
                metaChip(TradeDisplay.quantityBadgeText(trade.quantity))
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func sharedTradePricesRow(_ trade: Trade) -> some View {
        HStack(spacing: ExperienceSpacing.md) {
            priceColumn(title: "Entry", value: TradeDisplay.priceText(trade.entryPrice))
            Spacer(minLength: 0)
            priceColumn(title: "Exit", value: TradeDisplay.priceText(trade.exitPrice))
        }
    }

    private func sharedTradeDateRow(_ trade: Trade) -> some View {
        Text(TradeDisplay.dateTimeText(trade.entryAt))
            .experienceStyle(.caption2, color: tertiaryTextColor)
            .lineLimit(1)
    }

    private func metaChip(_ title: String, emphasized: Bool = false) -> some View {
        Text(title)
            .experienceStyle(
                .caption2,
                color: emphasized ? secondaryTextColor : tertiaryTextColor
            )
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                (isOutgoing ? colors.onAccent : colors.primaryText)
                    .opacity(emphasized ? 0.14 : 0.08)
            )
            .clipShape(Capsule())
    }

    private func priceColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: tertiaryTextColor)
            Text(value)
                .experienceStyle(.caption, color: secondaryTextColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func modeLabel(for trade: Trade) -> String? {
        if let badge = trade.publicAccountBadge?.trimmingCharacters(in: .whitespacesAndNewlines),
           !badge.isEmpty
        {
            return badge
        }
        return TradeDisplay.tradeModeFallbackTitle(trade.mode)
    }

    private func displayNote(for trade: Trade) -> String? {
        let caption = trade.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trade.notePreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: String?
        if let caption, !caption.isEmpty {
            raw = caption
        } else if let preview, !preview.isEmpty {
            raw = preview
        } else {
            raw = nil
        }
        guard let raw else { return nil }
        guard raw.count > 120 else { return raw }
        return String(raw.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private var accessibilityLabel: String {
        guard let trade else {
            return "Shared trade loading"
        }
        var parts = [
            "Shared trade",
            trade.symbol.ticker,
            TradeDisplay.pnlText(trade.realizedPnL),
            TradeDisplay.sideTitle(trade.side),
        ]
        if let mode = modeLabel(for: trade) {
            parts.append(mode)
        }
        parts.append(TradeDisplay.dateTimeText(trade.entryAt))
        return parts.joined(separator: ", ")
    }
}

private struct SharedTradeMediaBleedModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, -(ExperienceSpacing.sm + 2))
                .padding(.top, -ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.xxs)
        } else {
            content
        }
    }
}
