import SwiftUI

/// Permanent Trade detail destination — analysis-focused journal experience.
///
/// Likes / comments stay on public Profile (and Feed) cards — not on this screen.
struct TradeDetailView: View {
    @State private var viewModel: TradeDetailViewModel
    @State private var tradeAI: TradeAISectionViewModel
    @State private var showsDeleteConfirm = false
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private let entryExitColumns = [
        GridItem(.flexible(), spacing: ExperienceSpacing.md),
        GridItem(.flexible(), spacing: ExperienceSpacing.md),
    ]

    private let badgeColumns = [
        GridItem(.adaptive(minimum: 52), spacing: ExperienceSpacing.xs, alignment: .leading),
    ]

    init(tradeID: TradeID, data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: TradeDetailViewModel(
                tradeID: tradeID,
                trades: data.trades,
                profiles: data.profiles,
                session: data.session,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        _tradeAI = State(
            initialValue: TradeAISectionViewModel(tradeID: tradeID, ai: data.ai)
        )
        self.imagePipeline = data.imagePipeline
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
        .experienceNavigationTitle(viewModel.trade?.symbol.ticker ?? "Trade")
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.loadIfNeeded()
            tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
            await tradeAI.loadHistoryIfNeeded()
        }
        .onChange(of: viewModel.trade?.id) { _, _ in
            tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .onChange(of: viewModel.notes.count) { _, _ in
            tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
            tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .onAppear {
            tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .confirmationDialog(
            "Delete Trade?",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Trade", role: .destructive) {
                Task { _ = await viewModel.deleteTrade() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Couldn't delete trade",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.deleteErrorMessage = nil }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        .accessibilityIdentifier("detail.trade.root")
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let trade = viewModel.trade {
                    identityHeader(trade)
                        .padding(.horizontal, ExperienceSpacing.lg)
                        .padding(.top, ExperienceSpacing.sm)
                        .padding(.bottom, ExperienceSpacing.md)

                    // Omit media entirely when there is no screenshot — no empty placeholder.
                    if let media = viewModel.mediaReference {
                        TradeDetailMediaView(
                            reference: media,
                            imagePipeline: imagePipeline
                        )
                    }

                    tradeBody(trade)
                        .padding(.horizontal, ExperienceSpacing.lg)
                        .padding(.top, ExperienceSpacing.md)
                        .padding(.bottom, ExperienceSpacing.xl)
                }
            }
        }
        .overlay {
            if viewModel.isDeleting {
                ProgressView("Deleting…")
                    .padding(ExperienceSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ExperienceRadius.md))
            }
        }
    }

    // MARK: - Header

    private func identityHeader(_ trade: Trade) -> some View {
        DetailIdentityHeader(
            initials: viewModel.authorInitials,
            avatar: viewModel.authorAvatar,
            displayName: viewModel.authorDisplayName,
            username: viewModel.authorUsername,
            subtitle: viewModel.accountIdentityLine,
            dateText: TradeDisplay.dateText(trade.entryAt),
            isOwner: viewModel.isOwner,
            onEdit: viewModel.isOwner ? { viewModel.editTrade() } : nil,
            onDelete: viewModel.isOwner ? {
                ExperienceHaptics.play(.warning)
                showsDeleteConfirm = true
            } : nil,
            accessibilityIdentifier: "detail.trade.identity"
        )
    }

    // MARK: - Body

    private func tradeBody(_ trade: Trade) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
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

            TradeAISectionView(viewModel: tradeAI)
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
}
