import SwiftUI

struct TradingRulesComplianceDetailView: View {
    enum AnalyticsPresentation {
        case fullAnalytics
        case freeTierBasic
    }

    @Bindable private var session = TradingRulesComplianceSessionStore.shared
    @Bindable var scopeController: TradingRulesAnalyticsScopeController
    var scrollAnchor: FeedListScrollAnchor
    let navigationCoordinator: NavigationCoordinator
    let detailCache: DetailPresentationCache
    let loadDependencies: TradingRulesComplianceLoadDependencies
    var presentation: AnalyticsPresentation = .fullAnalytics
    let onRetry: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.stackNavigation) private var stackNavigation

    var body: some View {
        Group {
            if let error = session.loadError {
                ExperienceErrorState(
                    title: "Couldn't load trading rules analytics",
                    message: error,
                    onRetry: onRetry
                )
            } else if !session.ready {
                ProgressView("Loading trading rules analytics…")
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
                ProgressView("Loading trading rules analytics…")
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
        .sheet(isPresented: $scopeController.showsTimePeriodSheet) {
            TradingRulesAnalyticsTimePeriodSheet(scope: scopeController)
        }
        .sheet(isPresented: $scopeController.showsFiltersSheet) {
            TradingRulesAnalyticsFiltersSheet(scope: scopeController)
                .onAppear { scopeController.prepareDraftScopeFilters() }
        }
        .onChange(of: scopeClientScopeToken) { _, _ in
            scopeController.scheduleRecompute(dependencies: loadDependencies)
        }
    }

    private var scopeClientScopeToken: String {
        let filter = scopeController.clientScopeFilter()
        return PsychologyAnalyticsScopeResolver.fingerprint(scope: filter)
    }

    private func scrollContent(result: TradingRulesComplianceAnalytics.Result) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                if presentation == .fullAnalytics {
                    TradingRulesAnalyticsFilterBar(
                        scope: scopeController,
                        onManageAccounts: { navigationCoordinator.pushHome(.settings(.tradingAccounts)) },
                        onFiltersTap: {
                            scopeController.prepareDraftScopeFilters()
                            scopeController.showsFiltersSheet = true
                        }
                    )
                    .padding(ExperienceSpacing.sm)
                    .experienceTradingRulesCard(prominence: .standard)
                } else if !session.scopeLabel.isEmpty {
                    Text(session.scopeLabel)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.xs)
                }

                if session.isProvisionalCompliance {
                    Text("Preliminary — full trade history is still loading. Numbers may change.")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .padding(ExperienceSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                        .accessibilityIdentifier("tradingRulesAnalytics.provisional")
                }

                TradingRulesComplianceSection(
                    analytics: result,
                    presentation: presentation == .freeTierBasic ? .freeOverview : .expandedAnalyticsPage,
                    zeroEvalHint: zeroEvalHint(for: result),
                    personalInsights: session.personalInsights,
                    activeDateRange: scopeController.dateRange,
                    usesCustomDateRange: scopeController.customDateInterval != nil,
                    onOpenTrade: presentation == .fullAnalytics ? { tradeID in
                        preserveScrollOffset()
                        navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                    } : nil,
                    onOpenRule: presentation == .fullAnalytics ? { rule in
                        preserveScrollOffset()
                        navigationCoordinator.pushTradingRulesRuleDetail(rule.rawValue)
                    } : nil,
                    onOpenDay: presentation == .fullAnalytics ? { dayKey in
                        preserveScrollOffset()
                        navigationCoordinator.pushTradingRulesDayDetail(dayKey)
                    } : nil
                )

                if presentation == .freeTierBasic {
                    TradingRulesPremiumAnalyticsLockedSection()
                }
            }
            .padding(ExperienceSpacing.md)
        }
        .id(TradingRulesAnalyticsScrollSurfaceIdentity.analyticsList)
        .scrollPosition(scrollAnchor.binding)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offsetY in
            scrollAnchor.noteMeasuredContentOffset(offsetY)
        }
    }

    private func preserveScrollOffset() {
        TradingRulesAnalyticsScrollStore.remember(scrollAnchor.offset)
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
            TradingRulesAnalyticsFilterBar(
                scope: scopeController,
                onManageAccounts: { navigationCoordinator.pushHome(.settings(.tradingAccounts)) },
                onFiltersTap: {
                    scopeController.prepareDraftScopeFilters()
                    scopeController.showsFiltersSheet = true
                }
            )
            .padding(ExperienceSpacing.sm)
            .experienceTradingRulesCard(prominence: .standard)
            .padding(.horizontal, ExperienceSpacing.md)

            ExperienceEmptyState(
                icon: .filter,
                title: "No trades match this filter",
                message: """
                You have trading rules configured, but none of your trades match the current filter. Widen the date range or account selection — compliance is not 0%.
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