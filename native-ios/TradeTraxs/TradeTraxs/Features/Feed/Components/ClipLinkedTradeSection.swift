import SwiftUI

/// Compact linked-trade block for full-screen Clips overlays and clip detail.
struct ClipLinkedTradeSection: View {
    enum Style: Equatable {
        case clipsOverlay
        case detailBody
    }

    let trade: Trade
    var style: Style = .clipsOverlay
    /// Clip caption shown above this section, suppress duplicate trade description when identical.
    var displayedClipCaption: String? = nil
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private static let descriptionLineLimit = 3
    private var fields: ClipLinkedTradePresentation.Fields {
        ClipLinkedTradePresentation.fields(for: trade)
    }

    var body: some View {
        Button(action: onOpen) {
            Group {
                switch style {
                case .clipsOverlay:
                    overlayContent
                case .detailBody:
                    detailCardContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(
            ClipLinkedTradePresentation.accessibilitySummary(
                for: trade,
                description: Self.descriptionText(for: trade, clipCaption: displayedClipCaption)
            )
        )
        .accessibilityIdentifier("clips.linked.trade.\(trade.id.rawValue)")
    }

    /// Public caption first, then journal notes / preview when public text is absent.
    static func descriptionText(for trade: Trade, clipCaption: String? = nil) -> String? {
        let candidate =
            LinkedContentCaptionDedup.normalizedForComparison(trade.publicCaption)
            ?? LinkedContentCaptionDedup.normalizedForComparison(trade.notes)
            ?? LinkedContentCaptionDedup.normalizedForComparison(trade.notePreview)
        guard let candidate else { return nil }
        if LinkedContentCaptionDedup.shouldHideTradeDescription(
            displayedClipCaption: clipCaption,
            tradeDescription: candidate
        ) {
            return nil
        }
        return candidate
    }

    // MARK: - Detail card

    private var detailCardContent: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Linked Trade")
                .experienceStyle(.caption, color: colors.secondaryText)
                .fontWeight(.semibold)

            PublicTradeHeadlineRow(
                ticker: fields.ticker,
                realizedPnL: trade.realizedPnL
            )

            PublicTradeMetaChipRow(
                trade: trade,
                showsQuantity: false,
                showsSession: false,
                showsRiskReward: false
            )

            detailExecutionRow
            detailRiskRewardRow
            detailMetaRow

            if let description = Self.descriptionText(for: trade, clipCaption: displayedClipCaption) {
                Text(description)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .lineLimit(Self.descriptionLineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(ExperienceSpacing.sm)
        .background(
            colors.surfaceSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
    }

    private var detailExecutionRow: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            ClipLinkedTradeExecutionColumn(
                label: "Entry",
                price: fields.entryPrice,
                time: fields.entryTime,
                style: .detailBody
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if fields.exitPrice != nil || fields.exitTime != nil {
                ClipLinkedTradeExecutionColumn(
                    label: "Exit",
                    price: fields.exitPrice,
                    time: fields.exitTime,
                    style: .detailBody
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var detailRiskRewardRow: some View {
        if fields.targetedRr != nil || fields.realizedRr != nil {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                if let targetedRr = fields.targetedRr {
                    ClipLinkedTradeLabeledMetric(
                        label: "Targeted R:R",
                        value: targetedRr,
                        style: .detailBody
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let realizedRr = fields.realizedRr {
                    ClipLinkedTradeLabeledMetric(
                        label: "Realized R:R",
                        value: realizedRr,
                        style: .detailBody
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var detailMetaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
            Text(fields.tradeDate)
                .experienceStyle(.caption, color: colors.tertiaryText)
                .lineLimit(1)
            if let account = fields.accountCaption {
                Text("·")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                Text(account)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    // MARK: - Clips overlay

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Linked Trade")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .shadow(color: overlayShadowColor, radius: 2, y: 1)

            overlayHeadlineRow
            overlayEntryExitRow
            overlayRiskRewardRow

            Text(fields.tradeDate)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .shadow(color: overlayShadowColor, radius: 2, y: 1)
        }
    }

    private var overlayHeadlineRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(fields.pnlText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(pnlMetricColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(fields.ticker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(fields.sideTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(sideOverlayColor)
                .lineLimit(1)
        }
        .shadow(color: overlayShadowColor, radius: 2, y: 1)
    }

    @ViewBuilder
    private var overlayEntryExitRow: some View {
        if fields.entryPrice != nil || fields.exitPrice != nil {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                if let entryPrice = fields.entryPrice {
                    ClipLinkedTradeExecutionColumn(
                        label: "Entry",
                        price: entryPrice,
                        time: nil,
                        style: .clipsOverlay
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let exitPrice = fields.exitPrice {
                    ClipLinkedTradeExecutionColumn(
                        label: "Exit",
                        price: exitPrice,
                        time: nil,
                        style: .clipsOverlay
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var overlayRiskRewardRow: some View {
        if fields.targetedRr != nil || fields.realizedRr != nil {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                if let targetedRr = fields.targetedRr {
                    overlayRrChip(label: "Target", value: targetedRr)
                }
                if let realizedRr = fields.realizedRr {
                    overlayRrChip(label: "Realized", value: realizedRr)
                }
            }
        }
    }

    private func overlayRrChip(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
        }
        .lineLimit(1)
        .shadow(color: overlayShadowColor, radius: 2, y: 1)
    }

    private var pnlMetricColor: Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
        )
    }

    private var sideOverlayColor: Color {
        trade.side == .long ? Color.green.opacity(0.95) : Color.red.opacity(0.95)
    }

    private var overlayShadowColor: Color {
        .black.opacity(0.35)
    }
}

// MARK: - Shared metrics subviews

private struct ClipLinkedTradeExecutionColumn: View {
    let label: String
    let price: String?
    let time: String?
    let style: ClipLinkedTradeSection.Style

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(labelFont)
                .foregroundStyle(labelColor)
                .lineLimit(1)
            if let price {
                Text(price)
                    .font(priceFont)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
            }
            if let time {
                Text(time)
                    .font(timeFont)
                    .foregroundStyle(timeColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
            }
        }
        .modifier(OverlayTextShadowModifier(style: style))
        .accessibilityElement(children: .combine)
    }

    private var labelFont: Font {
        switch style {
        case .clipsOverlay: return .caption2
        case .detailBody: return .caption2
        }
    }

    private var priceFont: Font {
        switch style {
        case .clipsOverlay:
            return .system(.caption, design: .rounded).weight(.semibold)
        case .detailBody:
            return .system(.subheadline, design: .rounded).weight(.semibold)
        }
    }

    private var timeFont: Font {
        switch style {
        case .clipsOverlay: return .caption2
        case .detailBody: return .caption2
        }
    }

    private var labelColor: Color {
        switch style {
        case .clipsOverlay: return .white.opacity(0.75)
        case .detailBody: return colors.tertiaryText
        }
    }

    private var valueColor: Color {
        switch style {
        case .clipsOverlay: return .white.opacity(0.95)
        case .detailBody: return colors.primaryText
        }
    }

    private var timeColor: Color {
        switch style {
        case .clipsOverlay: return .white.opacity(0.82)
        case .detailBody: return colors.secondaryText
        }
    }
}

private struct ClipLinkedTradeLabeledMetric: View {
    let label: String
    let value: String
    let style: ClipLinkedTradeSection.Style

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
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OverlayTextShadowModifier: ViewModifier {
    let style: ClipLinkedTradeSection.Style

    func body(content: Content) -> some View {
        switch style {
        case .clipsOverlay:
            content.shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        case .detailBody:
            content
        }
    }
}