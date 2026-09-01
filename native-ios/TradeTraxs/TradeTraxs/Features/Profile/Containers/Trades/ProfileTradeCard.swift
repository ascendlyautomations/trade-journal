import SwiftUI

struct ProfileTradeCard: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let showsOwnerActions: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.themeColors) private var colors

    private var target: InteractionTarget { .trade(trade.id) }

    private var mediaReference: MediaReference? {
        ProfileCardMediaPresence.tradeMedia(in: trade)
    }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Group {
                    if let mediaReference {
                        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                            TradeImageView(
                                reference: mediaReference,
                                imagePipeline: imagePipeline
                            )
                            .accessibilityHidden(true)

                            tradeSummaryColumn
                        }
                    } else {
                        tradeSummaryColumn
                    }
                }
                .contentShape(Rectangle())
                .experienceDoubleTapLike(
                    target: target,
                    store: engagementStore,
                    onSingleTap: onOpen
                )

                if let note = trade.notePreview, !note.isEmpty {
                    Text(note)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .experienceDoubleTapLike(
                            target: target,
                            store: engagementStore,
                            onSingleTap: onOpen
                        )
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
        } preview: {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(trade.symbol.ticker)
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .experienceStyle(.metric, color: colors.primaryText)
                Text(TradeDisplay.sideTitle(trade.side))
                    .experienceStyle(.caption, color: colors.secondaryText)
                if let note = trade.notePreview, !note.isEmpty {
                    Text(note)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(3)
                }
            }
            .padding()
            .frame(width: 280, alignment: .leading)
            .background(colors.surfacePrimary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("profile.trades.card.\(trade.id.rawValue)")
    }

    private var tradeSummaryColumn: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            PublicTradeHeadlineRow(
                ticker: trade.symbol.ticker,
                realizedPnL: trade.realizedPnL
            )
            .accessibilityIdentifier("profile.trade.headline")

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

    private var metaRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if let accountBadge = trade.publicAccountBadge {
                ExperienceTag(title: accountBadge, tone: .info)
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
