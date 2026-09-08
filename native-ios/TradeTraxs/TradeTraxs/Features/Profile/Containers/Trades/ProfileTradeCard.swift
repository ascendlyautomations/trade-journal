import SwiftUI

struct ProfileTradeCard: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let showsOwnerActions: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onReport: (() -> Void)? = nil

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
                            TradeTraxsContentImage(
                                mediaID: trade.id.rawValue,
                                reference: mediaReference,
                                purpose: .tradeScreenshot,
                                imagePipeline: imagePipeline,
                                surface: .profile,
                                fixedSize: CGSize(width: 96, height: 96)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                            .accessibilityHidden(true)

                            tradeSummaryColumn
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                    vaultStore: vaultStore,
                    onCommentTap: onOpen,
                    vaultRef: ProfileCardMediaPresence.engagementVaultRef(
                        for: target,
                        profileIsOwner: showsOwnerActions
                    )
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            ContentOverflowMenu(
                isOwner: showsOwnerActions,
                onReport: onReport,
                onEdit: showsOwnerActions ? onEdit : nil,
                onDelete: showsOwnerActions ? onDelete : nil,
                accessibilityIdentifier: "profile.trade.overflow.\(trade.id.rawValue)"
            )
            .padding(ExperienceSpacing.xxs)
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
            ProfileTradeHeadlineRow(
                ticker: trade.symbol.ticker,
                realizedPnL: trade.realizedPnL
            )
            .accessibilityIdentifier("profile.trade.headline")

            HStack(spacing: ExperienceSpacing.xs) {
                Text(TradeDisplay.dateText(trade.createdAt))
                    .experienceStyle(.caption, color: colors.secondaryText)
                visibilityIcon
            }

            PublicTradeMetaChipRow(trade: trade, showsSession: false, layout: .wrap)
                .accessibilityIdentifier("profile.trade.badges")
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
        return "\(pnl), \(trade.symbol.ticker), \(side)"
    }
}

/// Profile → Trades headline: `P&L | TICKER` with space reserved for the overflow menu.
private struct ProfileTradeHeadlineRow: View {
    let ticker: String
    let realizedPnL: Money?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
            Text(TradeDisplay.pnlText(realizedPnL))
                .font(ExperienceTypography.headline.monospacedDigit())
                .foregroundStyle(
                    theme.metricColor(
                        for: NSDecimalNumber(decimal: realizedPnL?.amount ?? 0).doubleValue
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)

            Text("|")
                .font(ExperienceTypography.headline)
                .foregroundStyle(colors.tertiaryText)
                .accessibilityHidden(true)

            Text(ticker)
                .font(ExperienceTypography.headline)
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.trailing, ExperienceAccessibility.minTouchTarget + ExperienceSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
