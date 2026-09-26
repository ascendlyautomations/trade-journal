import SwiftUI

/// Shared trade detail shell — presentation differs by ``TradeDetailExperience``.
///
/// Prefer ``JournalTradeDetailView`` / ``SocialTradeDetailView`` at call sites.
struct TradeDetailView: View {
    @State private var viewModel: TradeDetailViewModel
    @State private var tradeAI: TradeAISectionViewModel?
    @State private var showsDeleteConfirm = false
    @State private var showsShareSheet = false
    @State private var showsVaultSheet = false
    @State private var contentRevealed = false
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment
    private let experience: TradeDetailExperience

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let commentsAnchorID = "trade.detail.comments"
    private static let sectionSpacing = ExperienceSpacing.md

    init(
        tradeID: TradeID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        experience: TradeDetailExperience
    ) {
        _viewModel = State(
            initialValue: TradeDetailViewModel(
                tradeID: tradeID,
                trades: data.trades,
                tradeDetailRepository: data.tradeDetailRepository,
                profiles: data.profiles,
                session: data.session,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                rpc: data.rpc,
                experience: experience
            )
        )
        if experience == .journal {
            _tradeAI = State(
                initialValue: TradeAISectionViewModel(tradeID: tradeID, ai: data.ai)
            )
        } else {
            _tradeAI = State(initialValue: nil)
        }
        self.imagePipeline = data.imagePipeline
        self.data = data
        self.experience = experience
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
        .toolbar {
            if experience == .journal, viewModel.isOwner, viewModel.trade != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ownerOverflowMenu
                }
            }
        }
        .task {
            viewModel.loadIfNeeded()
            if experience == .social {
                let target = socialEngagementTarget(for: viewModel.tradeID)
                data.engagementStore.prefetch([target])
            }
            data.vaultStore.prefetch([
                VaultContentRef(contentType: .trade, contentID: viewModel.tradeID.rawValue),
            ])
            if let tradeAI {
                tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
                await tradeAI.loadHistoryIfNeeded()
            }
        }
        .onChange(of: viewModel.trade?.id) { _, _ in
            tradeAI?.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .onChange(of: viewModel.notes.count) { _, _ in
            tradeAI?.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
            tradeAI?.updateContext(trade: viewModel.trade, notes: viewModel.notes)
        }
        .onAppear {
            tradeAI?.updateContext(trade: viewModel.trade, notes: viewModel.notes)
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
        .sheet(isPresented: $showsShareSheet) {
            if let trade = viewModel.trade, let url = DetailContentLink.trade(trade.id).url {
                DetailShareSheet(items: [shareText(for: trade), url])
            }
        }
        .sheet(isPresented: $showsVaultSheet) {
            VaultDestinationSheet(ref: tradeVaultRef, store: data.vaultStore)
        }
        .accessibilityIdentifier(
            experience == .journal ? "detail.trade.journal" : "detail.trade.social"
        )
        .experienceDetailEntry(revealed: contentRevealed, reduceMotion: reduceMotion)
        .onAppear {
            guard !contentRevealed else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                contentRevealed = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                    if let trade = viewModel.trade {
                        if showsSocialIdentityHeader {
                            identityHeader(trade)
                        }

                        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                            if experience == .journal {
                                journalTradeContent(trade)
                            } else {
                                socialTradeContent(trade, scrollProxy: proxy)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.xs)
                .padding(.bottom, ExperienceSpacing.lg)
            }
        }
        .overlay {
            if viewModel.isDeleting {
                ProgressView("Deleting…")
                    .padding(ExperienceSpacing.md)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
            }
        }
    }

    private var showsSocialIdentityHeader: Bool {
        experience == .social || (experience == .journal && !viewModel.isOwner)
    }

    // MARK: - Header / toolbar

    private func identityHeader(_ trade: Trade) -> some View {
        DetailIdentityHeader(
            initials: viewModel.authorInitials,
            avatar: viewModel.authorAvatar,
            displayName: viewModel.authorDisplayName,
            username: viewModel.authorUsername,
            subtitle: viewModel.accountIdentityLine,
            dateText: TradeDisplay.dateText(trade.entryAt),
            isOwner: viewModel.isOwner,
            contentLink: .trade(trade.id),
            ownerProfileID: trade.ownerProfileID,
            shareText: shareText(for: trade),
            editTitle: "Edit Trade",
            deleteTitle: "Delete Trade",
            onEdit: viewModel.isOwner ? { viewModel.editTrade() } : nil,
            onDelete: viewModel.isOwner ? {
                ExperienceHaptics.play(.warning)
                showsDeleteConfirm = true
            } : nil,
            vaultRef: VaultContentRef(contentType: .trade, contentID: trade.id.rawValue),
            accessibilityIdentifier: "detail.trade.identity"
        )
    }

    private var tradeVaultRef: VaultContentRef {
        VaultContentRef(contentType: .trade, contentID: viewModel.tradeID.rawValue)
    }

    private var isTradeVaulted: Bool {
        data.vaultStore.state(for: tradeVaultRef).isVaulted
    }

    private var ownerOverflowMenu: some View {
        DetailOverflowMenu(
            isOwner: true,
            onShare: viewModel.trade.map { _ in { showsShareSheet = true } },
            onCopyLink: viewModel.trade.map { trade in
                { DetailOverflowActions.copyLink(.trade(trade.id)) }
            },
            onAddToVault: isTradeVaulted ? nil : { openVaultSheet() },
            onManageInVault: isTradeVaulted ? { openVaultSheet() } : nil,
            editTitle: "Edit Trade",
            deleteTitle: "Delete Trade",
            onEdit: { viewModel.editTrade() },
            onDelete: {
                ExperienceHaptics.play(.warning)
                showsDeleteConfirm = true
            },
            accessibilityIdentifier: "detail.trade.overflow"
        )
    }

    private func openVaultSheet() {
        data.vaultStore.loadFoldersIfNeeded()
        showsVaultSheet = true
    }

    private func shareText(for trade: Trade) -> String {
        let pnl = TradeDisplay.pnlText(trade.realizedPnL)
        let side = trade.side == .long ? "Long" : "Short"
        return "\(trade.symbol.ticker) \(side) \(pnl) on TradeTraxs"
    }

    // MARK: - Journal (owner analytics)

    @ViewBuilder
    private func journalTradeContent(_ trade: Trade) -> some View {
        TradeDetailCompactHeader(
            trade: trade,
            accountLine: viewModel.accountSummaryLine
        )
        .accessibilityIdentifier("detail.trade.headline")

        TradeDetailQuickStatsSection(trade: trade)

        if let media = viewModel.mediaReference {
            TradeDetailMediaView(
                mediaID: trade.id.rawValue,
                reference: media,
                imagePipeline: imagePipeline
            )
        }

        if let cohort = viewModel.ownerAnalytics?.cohort {
            TradeDetailComparisonSection(
                trade: trade,
                cohort: cohort,
                quickInsight: viewModel.ownerAnalytics?.quickInsight
            )
        }

        if let tickerHistory = viewModel.ownerAnalytics?.tickerHistory {
            TradeDetailTickerHistorySection(history: tickerHistory)
        }

        TradeDetailJournalSection(
            trade: trade,
            notes: viewModel.notes,
            isOwner: viewModel.isOwner
        )

        if let tradeAI {
            TradeAISectionView(viewModel: tradeAI)
        }
    }

    // MARK: - Social (public)

    @ViewBuilder
    private func socialTradeContent(_ trade: Trade, scrollProxy: ScrollViewProxy) -> some View {
        if let media = viewModel.mediaReference {
            TradeDetailMediaView(
                mediaID: trade.id.rawValue,
                reference: media,
                imagePipeline: imagePipeline
            )
        }

        TradeDetailCompactHeader(
            trade: trade,
            accountLine: viewModel.accountIdentityLine
        )
        .accessibilityIdentifier("detail.trade.headline")

        PublicTradeMetaChipRow(trade: trade, layout: .wrap)
            .accessibilityIdentifier("detail.trade.badges")

        TradeDetailQuickStatsSection(trade: trade)

        if let description = trade.publicCaption?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !description.isEmpty
        {
            Text(description)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.trade.description")
        }

        EngagementBar(
            target: socialEngagementTarget(for: trade.id),
            store: data.engagementStore,
            vaultStore: data.vaultStore,
            onCommentTap: {
                withAnimation(
                    ExperienceMotion.preferred(
                        ExperienceMotion.selection,
                        reduceMotion: reduceMotion
                    )
                ) {
                    scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                }
            },
            vaultRef: VaultContentRef(contentType: .trade, contentID: trade.id.rawValue)
        )
        CommentsSectionView(
            target: socialEngagementTarget(for: trade.id),
            contentOwnerUserID: trade.ownerProfileID.rawValue,
            data: data
        )
        .id(Self.commentsAnchorID)
    }

    private func socialEngagementTarget(for tradeID: TradeID) -> InteractionTarget {
        data.detailCache.feedEngagementTarget(forTrade: tradeID) ?? .trade(tradeID)
    }
}

private struct DetailShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
