import SwiftUI

struct TradingRulesComplianceDetailView: View {
    enum AnalyticsPresentation {
        case fullAnalytics
        case freeTierBasic
        /// Free tier sample preview — interactive charts and drill-down, demo data only.
        case freeSamplePreview
    }

    @Bindable private var session: TradingRulesComplianceSessionStore
    @Bindable var scopeController: TradingRulesAnalyticsScopeController
    var scrollAnchor: FeedListScrollAnchor
    let navigationCoordinator: NavigationCoordinator
    let detailCache: DetailPresentationCache
    let loadDependencies: TradingRulesComplianceLoadDependencies
    var presentation: AnalyticsPresentation = .fullAnalytics
    let onRetry: () -> Void
    /// When set (TraxsPro preview), scope edits recompute local bundled analytics instead of production loaders.
    var onScopeRecompute: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @Environment(\.stackNavigation) private var stackNavigation

    init(
        scopeController: TradingRulesAnalyticsScopeController,
        scrollAnchor: FeedListScrollAnchor,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        loadDependencies: TradingRulesComplianceLoadDependencies,
        sessionStore: TradingRulesComplianceSessionStore? = nil,
        presentation: AnalyticsPresentation = .fullAnalytics,
        onRetry: @escaping () -> Void,
        onScopeRecompute: (() -> Void)? = nil
    ) {
        let resolved = sessionStore ?? TradingRulesCompliancePresentationStores.store(detailCache: detailCache)
        _session = Bindable(resolved)
        _scopeController = Bindable(scopeController)
        self.scrollAnchor = scrollAnchor
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.loadDependencies = loadDependencies
        self.presentation = presentation
        self.onRetry = onRetry
        self.onScopeRecompute = onScopeRecompute
    }

    private var allowsInteractiveDrillDown: Bool {
        presentation == .fullAnalytics || presentation == .freeSamplePreview
    }

    var body: some View {
        let renderBranch = RulesPreviewDebugLog.detailViewBranch(session: session)
        Group {
            if let error = session.loadError {
                ExperienceErrorState(
                    title: "Couldn't load trading rules analytics",
                    message: error,
                    onRetry: onRetry
                )
            } else if !session.ready {
                ExperienceLoadingSpinner(message: "Loading trading rules analytics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !session.hasConfiguredRules {
                noRulesConfiguredState
            } else if session.insufficientScope {
                insufficientScopeState
            } else if let result = session.result {
                scrollContent(result: result)
            } else if session.scopedTradeCount == 0 {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No trades in scope",
                    message: "Widen the date range or account filter to see rule compliance for this scope."
                )
            } else {
                ExperienceLoadingSpinner(message: "Calculating rule compliance…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Trading Rules Analytics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Trading Rules", systemImage: AppIcon.settings.systemName) {
                    ExperienceHaptics.play(.selection)
                    stackNavigation?.pushSettings(.tradingAnalytics)
                }
                .accessibilityLabel("Trading Rules settings")
                .accessibilityIdentifier("tradingRulesAnalytics.settings")
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.detail")
        .onAppear {
            RulesPreviewDebugLog.log(
                "TradingRulesComplianceDetailView render branch=\(renderBranch) presentation=\(presentation) store=\(RulesPreviewDebugLog.storeID(session)) \(RulesPreviewDebugLog.describe(session: session))"
            )
        }
        .onChange(of: session.contentRevision) { _, _ in
            let branch = RulesPreviewDebugLog.detailViewBranch(session: session)
            RulesPreviewDebugLog.log(
                "TradingRulesComplianceDetailView contentRevision branch=\(branch) \(RulesPreviewDebugLog.describe(session: session))"
            )
        }
        .sheet(isPresented: $scopeController.showsTimePeriodSheet) {
            TradingRulesAnalyticsTimePeriodSheet(scope: scopeController)
        }
        .sheet(isPresented: $scopeController.showsFiltersSheet) {
            TradingRulesAnalyticsFiltersSheet(scope: scopeController)
                .onAppear { scopeController.prepareDraftScopeFilters() }
        }
        .onChange(of: scopeClientScopeToken) { _, _ in
            if let onScopeRecompute {
                onScopeRecompute()
            } else {
                scopeController.scheduleRecompute(dependencies: loadDependencies)
            }
        }
    }

    private var scopeClientScopeToken: String {
        let filter = scopeController.clientScopeFilter()
        return PsychologyAnalyticsScopeResolver.fingerprint(scope: filter)
    }

    private func scrollContent(result: TradingRulesComplianceAnalytics.Result) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if presentation == .fullAnalytics {
                    analyticsFilterBar
                } else if !session.scopeLabel.isEmpty {
                    Text(session.scopeLabel)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                }

                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    if TradingRulesAnalyticsPreviewSupport.usesBundledSampleDataPlane(
                        detailCache: detailCache
                    ) {
                        sampleDataNotice
                    }
                    if session.isProvisionalCompliance {
                        Text("Preliminary, full trade history is still loading. Numbers may change.")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .padding(ExperienceSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .experienceDashboardNestedCard(cornerRadius: ExperienceRadius.sm)
                            .accessibilityIdentifier("tradingRulesAnalytics.provisional")
                    }

                    TradingRulesComplianceSection(
                        analytics: result,
                        presentation: sectionPresentation,
                        zeroEvalHint: zeroEvalHint(for: result),
                        personalInsights: session.personalInsights,
                        activeDateRange: scopeController.dateRange,
                        usesCustomDateRange: scopeController.customDateInterval != nil,
                        onOpenTrade: allowsInteractiveDrillDown ? { tradeID in
                            guard allowsSampleTradeNavigation(tradeID) else { return }
                            preserveScrollOffset()
                            navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                        } : nil,
                        onOpenRule: allowsInteractiveDrillDown ? { rule in
                            preserveScrollOffset()
                            navigationCoordinator.pushTradingRulesRuleDetail(rule.rawValue)
                        } : nil,
                        onOpenDay: allowsInteractiveDrillDown ? { dayKey in
                            preserveScrollOffset()
                            navigationCoordinator.pushTradingRulesDayDetail(dayKey)
                        } : nil,
                        onOpenTrends: allowsInteractiveDrillDown ? {
                            preserveScrollOffset()
                            navigationCoordinator.pushTradingRulesTrends()
                        } : nil,
                        onOpenViolationHistory: allowsInteractiveDrillDown ? {
                            preserveScrollOffset()
                            navigationCoordinator.pushTradingRulesViolationHistory()
                        } : nil
                    )

                    if presentation == .freeTierBasic {
                        TradingRulesPremiumAnalyticsLockedSection()
                    } else if presentation == .freeSamplePreview {
                        MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                            feature: .premiumAnalytics,
                            previewFeature: .tradingRules,
                            previewEntryPoint: .tradingRulesGate,
                            previewAccessibilityIdentifier: "tradingRulesAnalytics.sample.preview",
                            unlockAccessibilityIdentifier: "tradingRulesAnalytics.sample.exploreTraxsPro"
                        )
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.bottom, ExperienceSpacing.md)
            }
            .padding(.top, ExperienceSpacing.sm)
        }
        .id(TradingRulesAnalyticsScrollSurfaceIdentity.analyticsList)
        .scrollPosition(scrollAnchor.binding)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offsetY in
            scrollAnchor.noteMeasuredContentOffset(offsetY)
        }
    }

    private var sectionPresentation: TradingRulesComplianceSection.Presentation {
        switch presentation {
        case .freeTierBasic:
            return .freeOverview
        case .freeSamplePreview:
            return .freeSamplePreview
        case .fullAnalytics:
            return .expandedAnalyticsPage
        }
    }

    private var sampleDataNotice: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Sample data preview")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(MonetizationPlanCopy.tradingRulesAnalyticsPreviewSampleDataNote)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .standard)
        .accessibilityIdentifier("tradingRulesAnalytics.sampleDataBanner")
    }

    private func allowsSampleTradeNavigation(_ tradeID: TradeID) -> Bool {
        TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: tradeID)
    }

    private func preserveScrollOffset() {
        TradingRulesAnalyticsScrollStore.remember(scrollAnchor.offset)
    }

    private var analyticsFilterBar: some View {
        TradingRulesAnalyticsFilterBar(
            scope: scopeController,
            onManageAccounts: { navigationCoordinator.pushHome(.settings(.tradingAccounts)) },
            onFiltersTap: {
                scopeController.prepareDraftScopeFilters()
                scopeController.showsFiltersSheet = true
            }
        )
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.top, ExperienceSpacing.xs)
        .padding(.bottom, ExperienceSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zeroEvalHint(for result: TradingRulesComplianceAnalytics.Result) -> String? {
        guard result.score.evaluated == 0 else { return nil }
        if let message = session.eligibility?.userMessage {
            return message
        }
        if result.score.unevaluated == 0 {
            return "No rule checks could run in this scope with your saved rule history."
        }
        return nil
    }

    private var insufficientScopeState: some View {
        VStack(spacing: ExperienceSpacing.md) {
            analyticsFilterBar

            ExperienceEmptyState(
                icon: .filter,
                title: "No trades match this filter",
                message: """
                You have trading rules configured, but none of your trades match the current filter. Widen the date range or account selection, compliance is not 0%.
                """
            )
        }
    }

    private var noRulesConfiguredState: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ExperienceEmptyState(
                icon: .settings,
                title: "No trading rules yet",
                message: "Set sessions, caps, loss limits, and other rules in Settings to start tracking compliance."
            )
            Button {
                navigationCoordinator.pushHome(.settings(.tradingAnalytics))
            } label: {
                Text("Open Trading Rules")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, ExperienceSpacing.lg)
        }
    }
}