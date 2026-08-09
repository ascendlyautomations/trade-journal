import SwiftUI

/// Permanent Trade detail destination — Instagram-style hierarchy for Profile / Feed / Home.
struct TradeDetailView: View {
    @State private var viewModel: TradeDetailViewModel
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let entryExitColumns = [
        GridItem(.flexible(), spacing: ExperienceSpacing.md),
        GridItem(.flexible(), spacing: ExperienceSpacing.md),
    ]

    private let badgeColumns = [
        GridItem(.adaptive(minimum: 52), spacing: ExperienceSpacing.xs, alignment: .leading),
    ]

    init(tradeID: TradeID, data: DataEnvironment) {
        _viewModel = State(
            initialValue: TradeDetailViewModel(
                tradeID: tradeID,
                trades: data.trades,
                profiles: data.profiles,
                session: data.session,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.trade == nil:
                ExperienceLoadingSpinner(label: "Loading trade")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message) where viewModel.trade == nil:
                ExperienceErrorState(
                    title: "Couldn't load trade",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            default:
                content
            }
        }
        .experienceScreenBackground()
        .navigationTitle(viewModel.trade?.symbol.ticker ?? "Trade")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.loadIfNeeded()
            data.engagementStore.prefetch([.trade(viewModel.tradeID)])
        }
        .accessibilityIdentifier("detail.trade.root")
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let trade = viewModel.trade {
                        identityHeader(trade)
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(.top, ExperienceSpacing.sm)
                            .padding(.bottom, ExperienceSpacing.md)

                        TradeDetailMediaView(
                            reference: viewModel.mediaReference,
                            imagePipeline: imagePipeline
                        )

                        tradeBody(trade, scrollProxy: proxy)
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(.top, ExperienceSpacing.md)
                            .padding(.bottom, ExperienceSpacing.xl)
                    }
                }
            }
        }
    }

    // MARK: - Header (above image)

    private func identityHeader(_ trade: Trade) -> some View {
        DetailIdentityHeader(
            initials: viewModel.authorInitials,
            avatar: viewModel.authorAvatar,
            displayName: viewModel.authorDisplayName,
            username: viewModel.authorUsername,
            subtitle: viewModel.accountIdentityLine,
            dateText: TradeDisplay.dateText(trade.entryAt),
            isOwner: viewModel.isOwner,
            accessibilityIdentifier: "detail.trade.identity"
        )
    }

    // MARK: - Body (below image)

    private func tradeBody(_ trade: Trade, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            EngagementBar(
                target: .trade(trade.id),
                store: data.engagementStore,
                onCommentTap: {
                    withAnimation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                    ) {
                        scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                    }
                }
            )

            HStack(alignment: .firstTextBaseline) {
                Text(trade.symbol.ticker)
                    .experienceStyle(.title, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .experienceStyle(
                        .metricLarge,
                        color: theme.metricColor(
                            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                        )
                    )
            }
            .accessibilityIdentifier("detail.trade.headline")

            badgeRow(trade)

            descriptionSection(trade)

            entryExitInformation(trade)

            CommentsSectionView(target: .trade(trade.id), data: data)
                .id(Self.commentsAnchorID)
        }
    }

    private func badgeRow(_ trade: Trade) -> some View {
        // Account identity lives only in the header — do not repeat Funded/Eval/Live here.
        LazyVGrid(columns: badgeColumns, alignment: .leading, spacing: ExperienceSpacing.xs) {
            ExperienceTag(
                title: TradeDisplay.sideTitle(trade.side),
                tone: trade.side == .long ? .success : .error
            )
            if trade.riskReward != nil {
                ExperienceTag(title: TradeDisplay.rrText(trade.riskReward), tone: .info)
            }
            ExperienceTag(title: TradeDisplay.quantityBadgeText(trade.quantity), tone: .info)
            if let session = trade.sessionLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !session.isEmpty
            {
                ExperienceTag(title: session, tone: .info)
            }
        }
        .accessibilityIdentifier("detail.trade.badges")
    }

    @ViewBuilder
    private func descriptionSection(_ trade: Trade) -> some View {
        // Web `public_description` — unlabeled body; hidden when empty.
        if let description = trade.publicCaption?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !description.isEmpty
        {
            Text(description)
                .experienceStyle(.body, color: colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.trade.description")
        }
    }

    // Future: dedicated notes UI can slot in after description; ViewModel already loads notes.

    private func entryExitInformation(_ trade: Trade) -> some View {
        LazyVGrid(columns: entryExitColumns, alignment: .leading, spacing: ExperienceSpacing.md) {
            infoCell(title: "Entry Price", value: TradeDisplay.priceText(trade.entryPrice))
            infoCell(title: "Exit Price", value: TradeDisplay.priceText(trade.exitPrice))
            infoCell(title: "Entry Time", value: TradeDisplay.dateTimeText(trade.entryAt))
            infoCell(
                title: "Exit Time",
                value: trade.exitAt.map(TradeDisplay.dateTimeText) ?? "—"
            )
        }
        .accessibilityIdentifier("detail.trade.entryExit")
    }

    private func infoCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .experienceStyle(.caption, color: colors.tertiaryText)
            Text(value)
                .experienceStyle(.headline, color: colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.md)
        .background(colors.fillPrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private static let commentsAnchorID = "detail.trade.comments"
}
