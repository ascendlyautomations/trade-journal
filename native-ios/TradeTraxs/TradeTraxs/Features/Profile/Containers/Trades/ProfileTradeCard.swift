import SwiftUI

struct ProfileTradeCard: View {
    let summary: TradeSummary
    let imagePipeline: any ImagePipeline

    /// Non–Profile-tab surfaces (e.g. Calendar) that still hold full list trades.
    init(
        trade: Trade,
        imagePipeline: any ImagePipeline,
        engagementStore: EngagementStore,
        vaultStore: VaultStore,
        showsOwnerActions: Bool,
        onOpen: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onReport: (() -> Void)? = nil,
        profilePin: ProfilePinCallbacks? = nil
    ) {
        self.init(
            summary: TradeSummaryMapper.summary(fromPartialListTrade: trade),
            imagePipeline: imagePipeline,
            engagementStore: engagementStore,
            vaultStore: vaultStore,
            showsOwnerActions: showsOwnerActions,
            onOpen: onOpen,
            onShare: onShare,
            onEdit: onEdit,
            onDelete: onDelete,
            onReport: onReport,
            profilePin: profilePin
        )
    }

    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let showsOwnerActions: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onReport: (() -> Void)? = nil
    var profilePin: ProfilePinCallbacks? = nil

    init(
        summary: TradeSummary,
        imagePipeline: any ImagePipeline,
        engagementStore: EngagementStore,
        vaultStore: VaultStore,
        showsOwnerActions: Bool,
        onOpen: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onReport: (() -> Void)? = nil,
        profilePin: ProfilePinCallbacks? = nil
    ) {
        self.summary = summary
        self.imagePipeline = imagePipeline
        self.engagementStore = engagementStore
        self.vaultStore = vaultStore
        self.showsOwnerActions = showsOwnerActions
        self.onOpen = onOpen
        self.onShare = onShare
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onReport = onReport
        self.profilePin = profilePin
    }

    @Environment(\.themeColors) private var colors

    private var isPinnedToProfile: Bool {
        profilePin?.isPinned(.trade, summary.id.rawValue) ?? false
    }

    private var target: InteractionTarget { .trade(summary.id) }

    private var mediaReference: MediaReference? {
        ProfileCardMediaPresence.tradeMedia(in: summary)
    }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Group {
                    if let mediaReference {
                        ProfileCompactCardMediaSection {
                            ProfileCompactMediaThumbnail(
                                reference: mediaReference,
                                purpose: .tradeScreenshot,
                                imagePipeline: imagePipeline
                            )
                            .accessibilityHidden(true)
                        } metadata: {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                                tradeSummaryColumn

                                if let note = summary.notePreview, !note.isEmpty {
                                    Text(note)
                                        .experienceStyle(.footnote, color: colors.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                            tradeSummaryColumn

                            if let note = summary.notePreview, !note.isEmpty {
                                Text(note)
                                    .experienceStyle(.footnote, color: colors.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .experienceDoubleTapLike(
                    target: target,
                    store: engagementStore,
                    onSingleTap: onOpen
                )

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
                onPin: profilePin.map { pin in
                    {
                        pin.requestPin(
                            .trade,
                            summary.id.rawValue,
                            ProfilePinnedPreviewBuilder.from(summary: summary)
                        )
                    }
                },
                onUnpin: profilePin.map { pin in
                    {
                        pin.requestPin(
                            .trade,
                            summary.id.rawValue,
                            ProfilePinnedPreviewBuilder.from(summary: summary)
                        )
                    }
                },
                isPinnedToProfile: isPinnedToProfile,
                accessibilityIdentifier: "profile.trade.overflow.\(summary.id.rawValue)"
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
                Text(summary.symbol.ticker)
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(TradeDisplay.pnlText(summary.realizedPnL))
                    .experienceStyle(.metric, color: colors.primaryText)
                Text(TradeDisplay.sideTitle(summary.side))
                    .experienceStyle(.caption, color: colors.secondaryText)
                if let note = summary.notePreview, !note.isEmpty {
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
        .accessibilityIdentifier("profile.trades.card.\(summary.id.rawValue)")
    }

    private var tradeSummaryColumn: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            ProfileTradeHeadlineRow(
                ticker: summary.symbol.ticker,
                realizedPnL: summary.realizedPnL
            )
            .accessibilityIdentifier("profile.trade.headline")

            HStack(spacing: ExperienceSpacing.xs) {
                Text(TradeDisplay.dateText(summary.createdAt))
                    .experienceStyle(.caption, color: colors.secondaryText)
                visibilityIcon
            }

            PublicTradeMetaChipRow(summary: summary, showsSession: false, layout: .wrap)
                .accessibilityIdentifier("profile.trade.badges")
        }
    }

    @ViewBuilder
    private var visibilityIcon: some View {
        switch summary.visibility {
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
        let pnl = TradeDisplay.pnlText(summary.realizedPnL)
        let side = TradeDisplay.sideTitle(summary.side)
        return "\(pnl), \(summary.symbol.ticker), \(side)"
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
