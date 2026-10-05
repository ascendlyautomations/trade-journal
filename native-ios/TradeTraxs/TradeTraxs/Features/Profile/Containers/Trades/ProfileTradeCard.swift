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
        onDelete: (() -> Void)? = nil,
        isDeleteInProgress: Bool = false,
        onReport: (() -> Void)? = nil,
        profilePin: ProfilePinCallbacks? = nil,
        isProfilePinned: Bool = false
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
            isDeleteInProgress: isDeleteInProgress,
            onReport: onReport,
            profilePin: profilePin,
            isProfilePinned: isProfilePinned
        )
    }

    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let showsOwnerActions: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: (() -> Void)?
    var isDeleteInProgress: Bool = false
    var onReport: (() -> Void)? = nil
    var profilePin: ProfilePinCallbacks? = nil
    var isProfilePinned: Bool = false
    /// Grouped copy-action mode line from Profile display grouping — not recomputed from ``TradeSummary/accountMode``.
    var copyTradeModeSummaryLine: String? = nil

    init(
        summary: TradeSummary,
        imagePipeline: any ImagePipeline,
        engagementStore: EngagementStore,
        vaultStore: VaultStore,
        showsOwnerActions: Bool,
        onOpen: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        isDeleteInProgress: Bool = false,
        onReport: (() -> Void)? = nil,
        profilePin: ProfilePinCallbacks? = nil,
        isProfilePinned: Bool = false,
        copyTradeModeSummaryLine: String? = nil
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
        self.isDeleteInProgress = isDeleteInProgress
        self.onReport = onReport
        self.profilePin = profilePin
        self.isProfilePinned = isProfilePinned
        self.copyTradeModeSummaryLine = copyTradeModeSummaryLine
    }

    @Environment(\.themeColors) private var colors

    private var isPinnedToProfile: Bool {
        isProfilePinned || (profilePin?.isPinned(.trade, summary.id.rawValue) ?? false)
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
                editTitle: "Edit Trade",
                deleteTitle: "Delete Trade",
                onEdit: showsOwnerActions ? onEdit : nil,
                onDelete: showsOwnerActions && !isDeleteInProgress ? onDelete : nil,
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
                Button("Edit Trade", systemImage: "square.and.pencil", action: onEdit)
                if !isDeleteInProgress, let onDelete {
                    Button("Delete Trade", systemImage: "trash", role: .destructive, action: onDelete)
                }
            }
        } preview: {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xxs) {
                    Text(summary.symbol.ticker)
                        .experienceStyle(.headline, color: colors.primaryText)
                    if isPinnedToProfile {
                        ProfileContentPinIndicator()
                    }
                }
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

    private var profileCopyTradeModeLine: String? {
        ProfileCopyTradeModeSummaryText.renderedText(
            groupedLine: copyTradeModeSummaryLine,
            summaryLine: summary.copyTradePublicModeSummary
        )
    }

    private var tradeSummaryColumn: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            if summary.mode == .copyTraded {
                Text("Copy Traded")
                    .experienceStyle(.caption, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("profile.trade.copyTradedTitle")
            }

            ProfileTradeHeadlineRow(
                ticker: summary.symbol.ticker,
                realizedPnL: summary.realizedPnL,
                showsProfilePin: isPinnedToProfile
            )
            .accessibilityIdentifier("profile.trade.headline")

            HStack(spacing: ExperienceSpacing.xs) {
                Text(TradeDisplay.dateText(summary.createdAt))
                    .experienceStyle(.caption, color: colors.secondaryText)
                visibilityIcon
            }

            if summary.mode == .copyTraded {
                Text(
                    "\(TradeDisplay.sideTitle(summary.side)) • \(TradeDisplay.dateText(summary.entryAt))"
                )
                .experienceStyle(.caption, color: colors.secondaryText)
                .lineLimit(2)
                .accessibilityIdentifier("profile.trade.copySideTiming")

                ProfileCopyTradeModeSummaryText(
                    summary: summary,
                    groupedModeSummaryLine: copyTradeModeSummaryLine
                )
            }

            TradeExecutionMetricsTwoRowGrid(
                summary: summary,
                priceDisplay: .profileCardRounded
            )
            .accessibilityIdentifier("profile.trade.executionMetrics")
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
        let pin = isPinnedToProfile ? "Pinned to profile, " : ""
        return "\(pin)\(pnl), \(summary.symbol.ticker), \(side)"
    }
}

/// Profile copy card — render grouped ``copyTradePublicModeSummary`` only (never ``accountMode``).
private struct ProfileCopyTradeModeSummaryText: View {
    let summary: TradeSummary
    let groupedModeSummaryLine: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        let copySummary = summary.copyTradePublicModeSummary
        let rendered = Self.renderedText(
            groupedLine: groupedModeSummaryLine,
            summaryLine: copySummary
        )
        #if DEBUG
        let _ = ProfileCopySummaryDiagnostics.logCopyTradeCardRender(
            tradeID: summary.id.rawValue,
            isCopyTraded: summary.mode == .copyTraded,
            accountMode: summary.accountMode,
            copySummary: copySummary,
            renderedText: rendered
        )
        #endif
        if let rendered {
            Text(rendered)
                .experienceStyle(.caption, color: colors.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("profile.trade.copyModeSummary")
        }
    }

    static func renderedText(groupedLine: String?, summaryLine: String?) -> String? {
        let candidate = groupedLine ?? summaryLine
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// Profile → Trades headline: `P&L | TICKER` with space reserved for the overflow menu.
private struct ProfileTradeHeadlineRow: View {
    let ticker: String
    let realizedPnL: Money?
    var showsProfilePin: Bool = false

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

            if showsProfilePin {
                ProfileContentPinIndicator()
            }
        }
        .padding(.trailing, ExperienceAccessibility.minTouchTarget + ExperienceSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
