import SwiftUI

struct ProfileTradeCard: View {
    let trade: Trade
    let accountName: String?
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let showsOwnerActions: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var target: InteractionTarget { .trade(trade.id) }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                        TradeImageView(
                            reference: trade.thumbnail,
                            imagePipeline: imagePipeline
                        )
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(trade.symbol.ticker)
                                    .experienceStyle(.headline, color: colors.primaryText)
                                Spacer(minLength: ExperienceSpacing.xs)
                                Text(TradeDisplay.pnlText(trade.realizedPnL))
                                    .experienceStyle(
                                        .metric,
                                        color: theme.metricColor(
                                            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                                        )
                                    )
                            }

                            HStack(spacing: ExperienceSpacing.xs) {
                                ExperienceTag(
                                    title: TradeDisplay.sideTitle(trade.side),
                                    tone: trade.side == .long ? .success : .error
                                )
                                Text(TradeDisplay.dateText(trade.createdAt))
                                    .experienceStyle(.caption, color: colors.secondaryText)
                                visibilityIcon
                            }

                            metaRow
                        }
                    }
                }
                .buttonStyle(.plain)

                if let note = trade.notePreview, !note.isEmpty {
                    Text(note)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(2)
                        .onTapGesture(perform: onOpen)
                }

                EngagementBar(
                    target: target,
                    store: engagementStore,
                    onCommentTap: onOpen
                )
            }
        }
        .contextMenu {
            Button("Open", action: onOpen)
            Button("Share", systemImage: "square.and.arrow.up", action: onShare)
            if showsOwnerActions {
                Button("Edit", systemImage: "square.and.pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("profile.trades.card.\(trade.id.rawValue)")
    }

    private var metaRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if let accountName, !accountName.isEmpty {
                Text(accountName)
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .lineLimit(1)
            }
            Text(TradeDisplay.rrText(trade.riskReward))
                .experienceStyle(.caption, color: colors.tertiaryText)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var visibilityIcon: some View {
        switch trade.visibility {
        case .public:
            Image(systemName: "globe")
                .font(.caption2)
                .foregroundStyle(colors.tertiaryText)
                .accessibilityLabel("Public")
        case .private:
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(colors.tertiaryText)
                .accessibilityLabel("Private")
        case .followersOnly:
            Image(systemName: "person.2.fill")
                .font(.caption2)
                .foregroundStyle(colors.tertiaryText)
                .accessibilityLabel("Followers only")
        }
    }

    private var accessibilitySummary: String {
        let pnl = TradeDisplay.pnlText(trade.realizedPnL)
        let side = TradeDisplay.sideTitle(trade.side)
        return "\(trade.symbol.ticker), \(side), \(pnl)"
    }
}
