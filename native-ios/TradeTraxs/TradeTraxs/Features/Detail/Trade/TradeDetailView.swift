import SwiftUI

/// Shared trade detail shell, presentation differs by ``TradeDetailExperience``.
///
/// Prefer ``JournalTradeDetailView`` / ``SocialTradeDetailView`` at call sites.
struct TradeDetailView: View {
    @State private var viewModel: TradeDetailViewModel
    @State private var tradeAI: TradeAISectionViewModel?
    @State private var showsDeleteConfirm = false
    @State private var showsVaultSheet = false
    @State private var journalSharePresentation: JournalTradeShareSupport.Presentation?
    @State private var showsMakePublicCopyConfirm = false
    @State private var pendingCopyLinkTrade: Trade?
    @State private var isMakingPublicForCopyLink = false
    @State private var copyLinkPublicError: String?
    @State private var contentRevealed = false
    @State private var entitlementGateRevision = 0
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment
    private let experience: TradeDetailExperience

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.traxsProPreviewReadOnly) private var traxsProPreviewReadOnly

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
                ExperienceLoadingOverlay(label: "Loading trade")
            case .failed(let failure) where viewModel.trade == nil:
                ExperienceErrorState(
                    title: failure.title,
                    message: failure.message,
                    onRetry: failure.isRetryable ? { Task { await viewModel.refresh() } } : nil
                )
            default:
                content
                    .onAppear {
                        logContentRenderedIfReady()
                        if experience == .social {
                            socialEngagementTarget(for: viewModel.tradeID)
                                .recordCreatorImpression(surface: "detail")
                        }
                    }
            }
        }
        .id(viewModel.tradeID)
        .experienceScreenBackground(usesGroupedFillInLightMode: experience == .journal)
        .experienceNavigationTitle(viewModel.trade?.symbol.ticker ?? "Trade")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if experience == .journal, viewModel.isOwner, viewModel.trade != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ownerOverflowMenu
                }
            }
        }
        .task(id: viewModel.tradeID) {
            viewModel.loadIfNeeded()
            if experience == .social {
                let target = socialEngagementTarget(for: viewModel.tradeID)
                data.engagementStore.prefetch([target])
            }
            data.vaultStore.prefetch([tradeVaultRef])
            if let tradeAI {
                tradeAI.updateContext(trade: viewModel.trade, notes: viewModel.notes)
                if !restrictsPremiumTradeAI {
                    await tradeAI.loadHistoryIfNeeded()
                }
            }
        }
        .onChange(of: viewModel.trade?.id) { _, _ in
            logContentRenderedIfReady()
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
            viewModel.loadIfNeeded()
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
        .sheet(item: $journalSharePresentation) { presentation in
            SharedContentShareSheet(
                target: presentation.target,
                data: data,
                tradeOwnerShareAccess: experience == .journal && viewModel.isOwner
                    ? presentation.ownerAccess
                    : nil,
                onTradeVisibilityUpdated: experience == .journal && viewModel.isOwner
                    ? { viewModel.applyUpdated($0) }
                    : nil,
                onClose: { journalSharePresentation = nil }
            )
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
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .confirmationDialog(
            "Share this private trade?",
            isPresented: $showsMakePublicCopyConfirm,
            titleVisibility: .visible
        ) {
            Button("Make Public & Copy Link") {
                Task { await makePublicAndCopyLink() }
            }
            .disabled(isMakingPublicForCopyLink)
            Button("Cancel", role: .cancel) {
                pendingCopyLinkTrade = nil
            }
        } message: {
            Text(
                "This trade is private. People you share the link with can't open it on TradeTraxs unless sharing access is enabled."
            )
        }
        .alert(
            "Couldn't update trade",
            isPresented: Binding(
                get: { copyLinkPublicError != nil },
                set: { if !$0 { copyLinkPublicError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { copyLinkPublicError = nil }
        } message: {
            Text(copyLinkPublicError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if experience == .social, let trade = viewModel.trade {
                CommentsDetailChrome(
                    target: socialEngagementTarget(for: trade.id),
                    contentOwnerUserID: trade.ownerProfileID.rawValue,
                    data: data
                ) { commentsVM, currentUserID, _ in
                    socialDetailScroll(
                        trade: trade,
                        commentsVM: commentsVM,
                        currentUserID: currentUserID
                    )
                }
            } else {
                journalDetailScroll()
            }
        }
        .overlay {
            if viewModel.isDeleting {
                ExperienceLoadingSpinner(message: "Deleting…")
                    .padding(ExperienceSpacing.md)
                    .experienceFloatingPanelBackground(
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    )
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
            subtitle: experience == .social ? nil : viewModel.accountIdentityLine,
            dateText: experience == .social ? "" : TradeDisplay.dateText(trade.entryAt),
            relativePostedAt: viewModel.socialFeedPostPublishedAt,
            isOwner: viewModel.isOwner,
            contentLink: .trade(trade.id),
            ownerProfileID: trade.ownerProfileID,
            shareText: shareText(for: trade),
            editTitle: "Edit Trade",
            deleteTitle: "Delete Trade",
            onEdit: (viewModel.isOwner && !traxsProPreviewReadOnly) ? { viewModel.editTrade() } : nil,
            onDelete: (viewModel.isOwner && !traxsProPreviewReadOnly) ? {
                ExperienceHaptics.play(.warning)
                showsDeleteConfirm = true
            } : nil,
            onOpenAuthor: { viewModel.openAuthor() },
            vaultRef: tradeVaultRef,
            accessibilityIdentifier: "detail.trade.identity"
        )
    }

    /// Social detail uses the feed row’s vault key when the trade was opened from the feed.
    /// Journal keeps the trade record itself.
    private var tradeVaultRef: VaultContentRef {
        if experience == .social,
           let ref = VaultContentRef.from(socialEngagementTarget(for: viewModel.tradeID)) {
            return ref
        }
        return VaultContentRef(contentType: .trade, contentID: viewModel.tradeID.rawValue)
    }

    private var isTradeVaulted: Bool {
        data.vaultStore.state(for: tradeVaultRef).isVaulted
    }

    private var ownerOverflowMenu: some View {
        DetailOverflowMenu(
            isOwner: true,
            onShare: viewModel.trade.map { trade in
                { presentJournalShare(for: trade) }
            },
            onCopyLink: viewModel.trade.map { trade in
                { requestCopyLink(for: trade) }
            },
            onAddToVault: traxsProPreviewReadOnly ? nil : (isTradeVaulted ? nil : { openVaultSheet() }),
            onManageInVault: traxsProPreviewReadOnly ? nil : (isTradeVaulted ? { openVaultSheet() } : nil),
            editTitle: "Edit Trade",
            deleteTitle: "Delete Trade",
            onEdit: traxsProPreviewReadOnly ? nil : { viewModel.editTrade() },
            onDelete: traxsProPreviewReadOnly ? nil : {
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

    private func presentJournalShare(for trade: Trade) {
        guard experience == .journal, viewModel.isOwner else { return }
        presentShare(for: trade)
    }

    private func presentShare(for trade: Trade) {
        ExperienceHaptics.play(.selection)
        journalSharePresentation = JournalTradeShareSupport.presentation(for: trade)
    }

    private func requestCopyLink(for trade: Trade) {
        guard experience == .journal, viewModel.isOwner else {
            DetailOverflowActions.copyLink(.trade(trade.id))
            return
        }
        if trade.visibility == .private {
            pendingCopyLinkTrade = trade
            showsMakePublicCopyConfirm = true
            return
        }
        DetailOverflowActions.copyLink(.trade(trade.id))
    }

    private func makePublicAndCopyLink() async {
        guard let trade = pendingCopyLinkTrade else { return }
        pendingCopyLinkTrade = nil
        isMakingPublicForCopyLink = true
        defer { isMakingPublicForCopyLink = false }
        do {
            let updated = try await JournalTradeShareSupport.makePublicForSharing(
                trade: trade,
                trades: data.trades,
                session: data.session
            )
            viewModel.applyUpdated(updated)
            DetailOverflowActions.copyLink(.trade(updated.id))
        } catch {
            copyLinkPublicError = ProfileSectionSupport.message(for: error)
        }
    }

    // MARK: - Journal (owner analytics)

    @ViewBuilder
    private func journalTradeContent(_ trade: Trade) -> some View {
        TradeDetailGroupedSurface {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                TradeDetailCompactHeader(
                    trade: trade,
                    accountLine: viewModel.accountSummaryLine,
                    copyTradeOwnerDisplay: viewModel.copyTradeOwnerDisplay
                )
                TradeDetailQuickStatsContent(trade: trade)
                    .accessibilityIdentifier("detail.trade.quickStats")
            }
        }
        .accessibilityIdentifier("detail.trade.headline")

        TradeDetailJournalSection(
            trade: trade,
            notes: viewModel.notes,
            isOwner: viewModel.isOwner
        )

        if let media = viewModel.mediaReference {
            TradeDetailMediaView(
                mediaID: trade.id.rawValue,
                reference: media,
                imagePipeline: imagePipeline
            )
        }

        switch journalPremiumInsightsPresentation {
        case .unrestricted:
            if let analytics = viewModel.ownerAnalytics,
               let bundle = analytics.cohortBundle
            {
                TradeDetailComparisonSection(
                    trade: trade,
                    bundle: bundle,
                    filterContext: analytics.comparisonFilterContext,
                    quickInsight: analytics.quickInsight
                )
            }

            if let tickerHistory = viewModel.ownerAnalytics?.tickerHistory {
                TradeDetailTickerHistorySection(history: tickerHistory)
            }

            if let tradeAI {
                TradeAISectionView(viewModel: tradeAI)
            }
        case .lockedPreview, .verifyingEntitlement:
            TradeDetailTraxProUpsellSection(
                presentation: journalPremiumInsightsPresentation,
                trade: trade,
                profileID: journalViewerProfileID,
                onRetryEntitlementVerification: {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            )
        }
    }

    private var journalViewerProfileID: ProfileID? {
        SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
    }

    private var journalPremiumInsightsPresentation: ProPremiumFeaturePresentation {
        _ = entitlementGateRevision
        guard experience == .journal else { return .unrestricted }
        return ProMonetizationPolicy.premiumFeaturePresentation(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: journalViewerProfileID
        )
    }

    private var restrictsPremiumTradeAI: Bool {
        journalPremiumInsightsPresentation != .unrestricted
    }

    @ViewBuilder
    private func journalDetailScroll() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                if let trade = viewModel.trade {
                    if showsSocialIdentityHeader {
                        identityHeader(trade)
                    }
                    journalTradeContent(trade)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.lg)
        }
    }

    @ViewBuilder
    private func socialDetailScroll(
        trade: Trade,
        commentsVM: CommentsViewModel,
        currentUserID: ProfileID?
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                    if showsSocialIdentityHeader {
                        identityHeader(trade)
                    }
                    socialTradeContent(
                        trade,
                        scrollProxy: proxy,
                        commentsVM: commentsVM,
                        currentUserID: currentUserID
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.xs)
                .padding(.bottom, ExperienceSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .commentThreadScrollSupport(
                viewModel: commentsVM,
                scrollProxy: proxy,
                reduceMotion: reduceMotion
            )
            .detailCommentsScrollOnOpen(
                intent: .trade(viewModel.tradeID),
                anchorID: Self.commentsAnchorID,
                isContentReady: true,
                contentRevealed: contentRevealed,
                detailCache: data.detailCache,
                scrollProxy: proxy,
                reduceMotion: reduceMotion
            )
        }
    }

    // MARK: - Social (public)

    @ViewBuilder
    private func socialTradeContent(
        _ trade: Trade,
        scrollProxy: ScrollViewProxy,
        commentsVM: CommentsViewModel,
        currentUserID: ProfileID?
    ) -> some View {
        let hasSocialMedia = viewModel.mediaReference != nil || viewModel.visibleLinkedReel != nil

        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            if hasSocialMedia {
                SocialTradeDetailMediaSection(
                    tradeID: trade.id,
                    mediaReference: viewModel.mediaReference,
                    linkedReel: viewModel.visibleLinkedReel,
                    imagePipeline: imagePipeline,
                    onDoubleTapLike: {
                        Task {
                            await data.engagementStore.ensureLiked(
                                on: socialEngagementTarget(for: trade.id)
                            )
                        }
                    },
                    onOpenLinkedClip: {
                        guard let reel = viewModel.visibleLinkedReel else { return }
                        viewModel.openLinkedClip(reel.id)
                    }
                )

                socialEngagementBar(for: trade, scrollProxy: scrollProxy)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xxs)
            } else {
                socialEngagementBar(for: trade, scrollProxy: scrollProxy)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xxs)
            }

            TradeDetailGroupedSurface {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    SocialTradeDetailHeader(
                        trade: trade,
                        accountBadge: trade.mode == .copyTraded
                            ? nil
                            : TradeDisplay.socialHeaderAccountBadge(for: trade),
                        copyTradeSummary: trade.mode == .copyTraded
                            ? viewModel.socialCopyTradeModeSummary
                            : nil
                    )
                    TradeExecutionMetricsTwoRowGrid(
                        trade: trade,
                        contentAlignment: .centered,
                        showsPoints: false,
                        showsSocialExecutionDates: true
                    )
                    .accessibilityIdentifier("detail.trade.socialMetrics")
                }
            }
            .accessibilityIdentifier("detail.trade.headline")

            if let caption = viewModel.displayPublicCaption {
                SocialTradePublicCaptionSection(caption: caption)
            }

            CommentsSectionView(
                viewModel: commentsVM,
                currentUserID: currentUserID,
                imagePipeline: imagePipeline
            )
            .id(Self.commentsAnchorID)
        }
    }

    private func socialEngagementTarget(for tradeID: TradeID) -> InteractionTarget {
        data.detailCache.feedEngagementTarget(forTrade: tradeID) ?? .trade(tradeID)
    }

    private func socialEngagementBar(for trade: Trade, scrollProxy: ScrollViewProxy) -> some View {
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
            onShareTap: { presentShare(for: trade) },
            vaultRef: tradeVaultRef,
            visualStyle: .feedCard
        )
        .accessibilityIdentifier("detail.trade.engagement")
    }

    private func logContentRenderedIfReady() {
        #if DEBUG
        if viewModel.trade != nil {
            SharedTradeOpenDiagnostics.contentRendered(tradeID: viewModel.tradeID)
        }
        #endif
    }
}
