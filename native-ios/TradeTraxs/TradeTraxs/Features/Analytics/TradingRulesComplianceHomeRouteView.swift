import SwiftUI

struct TradingRulesComplianceHomeRouteView: View {
    let navigationCoordinator: NavigationCoordinator
    let data: DataEnvironment
    var embeddedInTraxsProPreview: Bool = false

    @State private var scopeController = TradingRulesAnalyticsScopeController()
    @State private var presentationRevision = 0
    @State private var loadOutcome: TradingRulesComplianceLoadOutcome = .ready
    @State private var isRefreshing = false
    @State private var loadGeneration = 0
    @State private var didAppearOnce = false
    @State private var scrollAnchor = TradingRulesAnalyticsScrollStore.sharedAnchor()
    @State private var skipNextAppearRefresh = false
    @State private var entitlementGateRevision = 0

    @Environment(\.navigationEnvironment) private var navigationEnvironment

    private var activeProfileID: ProfileID? {
        SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
    }

    private var loadDependencies: TradingRulesComplianceLoadDependencies {
        TradingRulesComplianceLoadDependencies(
            detailCache: data.detailCache,
            tradesRepository: data.trades,
            tradingPreferences: data.tradingPreferences
        )
    }

    private var showsEntitlementVerification: Bool {
        if embeddedInTraxsProPreview { return false }
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: activeProfileID
        )
    }

    private var restrictsFullAnalytics: Bool {
        if embeddedInTraxsProPreview { return false }
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictTradingRulesComplianceAnalytics(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: activeProfileID
        )
    }

    private var analyticsPresentation: TradingRulesComplianceDetailView.AnalyticsPresentation {
        if embeddedInTraxsProPreview || !restrictsFullAnalytics { return .fullAnalytics }
        return .freeSamplePreview
    }

    private var rulesPresentationStore: TradingRulesComplianceSessionStore {
        TradingRulesCompliancePresentationStores.store(for: data)
    }

    private var usesTraxsProPreviewDataPlane: Bool {
        embeddedInTraxsProPreview || TradingRulesCompliancePresentationStores.isPreviewDataPlane(data)
    }

    /// TraxsPro preview: require populated compliance math (Reports-style), not merely `ready`.
    private var canShowDetailView: Bool {
        guard let activeProfileID else { return false }
        guard rulesPresentationStore.profileID == activeProfileID, rulesPresentationStore.ready else {
            return false
        }
        if usesTraxsProPreviewDataPlane {
            return rulesPresentationStore.hasConfiguredRules
                && !rulesPresentationStore.insufficientScope
                && rulesPresentationStore.result != nil
        }
        return true
    }

    var body: some View {
        let homeBranch = RulesPreviewDebugLog.homeRouteBranch(
            embeddedInTraxsProPreview: embeddedInTraxsProPreview,
            showsEntitlementVerification: showsEntitlementVerification,
            canShowDetail: canShowDetailView,
            isRefreshing: isRefreshing,
            loadOutcome: loadOutcome,
            store: rulesPresentationStore
        )
        Group {
            if showsEntitlementVerification {
                TraxProEntitlementVerificationView(profileID: activeProfileID) {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            } else if canShowDetailView {
                TradingRulesComplianceDetailView(
                    scopeController: scopeController,
                    scrollAnchor: scrollAnchor,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    loadDependencies: loadDependencies,
                    sessionStore: rulesPresentationStore,
                    presentation: analyticsPresentation,
                    onRetry: { Task { await refreshAnalytics(forceReveal: false) } },
                    onScopeRecompute: usesTraxsProPreviewDataPlane
                        ? { republishPreviewRulesForCurrentScope() }
                        : nil
                )
                .id(presentationRevision)
                .overlay(alignment: .top) {
                    if isRefreshing {
                        ExperienceIndeterminateProgress()
                            .padding(.top, ExperienceSpacing.md)
                    }
                }
            } else if isRefreshing {
                ExperienceLoadingSpinner(message: "Loading trading rules analytics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .experienceScreenBackground()
            } else if case .failed(let message) = loadOutcome {
                ExperienceErrorState(
                    title: "Couldn't load trading rules analytics",
                    message: message,
                    onRetry: { Task { await refreshAnalytics(forceReveal: false) } }
                )
            } else {
                ExperienceLoadingSpinner(message: "Loading trading rules analytics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .experienceScreenBackground()
            }
        }
        .onAppear {
            RulesPreviewDebugLog.log(
                "TradingRulesComplianceHomeRouteView onAppear branch=\(homeBranch) usesPreviewPlane=\(usesTraxsProPreviewDataPlane) embedded=\(embeddedInTraxsProPreview) store=\(RulesPreviewDebugLog.storeID(rulesPresentationStore)) \(RulesPreviewDebugLog.describe(session: rulesPresentationStore))"
            )
        }
        .onChange(of: rulesPresentationStore.contentRevision) { _, _ in
            RulesPreviewDebugLog.log(
                "TradingRulesComplianceHomeRouteView contentRevision branch=\(RulesPreviewDebugLog.homeRouteBranch(embeddedInTraxsProPreview: embeddedInTraxsProPreview, showsEntitlementVerification: showsEntitlementVerification, canShowDetail: canShowDetailView, isRefreshing: isRefreshing, loadOutcome: loadOutcome, store: rulesPresentationStore)) \(RulesPreviewDebugLog.describe(session: rulesPresentationStore))"
            )
        }
        .task(id: taskIdentity) {
            guard !showsEntitlementVerification else { return }
            if !usesTraxsProPreviewDataPlane,
               restrictsFullAnalytics, let profileID = activeProfileID
            {
                TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
                    profileID: profileID,
                    detailCache: data.detailCache
                )
                scopeController.applyTraxsProPreviewScopeDefaultsIfNeeded()
            }
            await refreshAnalytics(forceReveal: true)
        }
        .task(id: restrictsFullAnalytics) {
            if usesTraxsProPreviewDataPlane {
                return
            }
            if restrictsFullAnalytics {
                guard let profileID = activeProfileID else { return }
                TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
                    profileID: profileID,
                    detailCache: data.detailCache
                )
                scopeController.applyTraxsProPreviewScopeDefaultsIfNeeded()
                await refreshAnalytics(forceReveal: true)
            } else {
                TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
                    profileID: activeProfileID,
                    detailCache: data.detailCache
                )
            }
        }
        .task(id: showsEntitlementVerification) {
            if showsEntitlementVerification {
                await TraxProEntitlementRefreshAction.refresh(data: data)
            }
        }
        .onAppear {
            guard didAppearOnce else {
                didAppearOnce = true
                return
            }
            if skipNextAppearRefresh {
                skipNextAppearRefresh = false
                return
            }
            guard !showsEntitlementVerification else { return }
            Task { await refreshAnalytics(forceReveal: false) }
        }
        .onChange(of: restrictsFullAnalytics) { _, _ in
            Task { await refreshAnalytics(forceReveal: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .onOwnerAccountMutation {
            scopeController.handleAccountMutation(detailCache: data.detailCache)
        }
        .onCopyTradingGroupsMutation {
            scopeController.handleCopyTradingGroupsMutation()
        }
        .onChange(of: analyticsStackDepth) { oldDepth, newDepth in
            if oldDepth == 0, newDepth == 1, isTradingRulesAnalyticsTop {
                TradingRulesAnalyticsScrollStore.resetForFreshNavigation()
            } else if newDepth > oldDepth, oldDepth >= 1 {
                TradingRulesAnalyticsScrollStore.remember(scrollAnchor.offset)
            } else if newDepth < oldDepth, newDepth == 1, isTradingRulesAnalyticsTop {
                skipNextAppearRefresh = true
                TradingRulesAnalyticsScrollStore.restore()
            } else if newDepth == 0 {
                TradingRulesAnalyticsScrollStore.clearRetainedOffset()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingPreferencesDidChange)) { _ in
            if !TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome,
               let profileID = activeProfileID
            {
                TradingRulesCompliancePreferencesCache.invalidate(profileID: profileID)
            }
            TradingRulesComplianceRecomputeCoordinator.reset()
            guard !showsEntitlementVerification else { return }
            Task { await refreshAnalytics(forceReveal: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingRulesComplianceOwnerTradesChanged)) { notification in
            guard let profileID = activeProfileID,
                  let raw = notification.userInfo?["profileID"] as? String,
                  raw == profileID.rawValue
            else { return }
            guard !showsEntitlementVerification else { return }
            Task { await refreshAnalytics(forceReveal: false) }
        }
    }

    private var taskIdentity: String {
        activeProfileID?.rawValue ?? "none"
    }

    private var analyticsStackDepth: Int {
        let store = navigationEnvironment.store
        switch store.selectedTab {
        case .home: return store.paths.home.count
        case .feed: return store.paths.feed.count
        case .messages: return store.paths.messages.count
        case .profile: return store.paths.profile.count
        case .create: return 0
        }
    }

    private var isTradingRulesAnalyticsTop: Bool {
        guard analyticsStackDepth == 1 else { return false }
        let store = navigationEnvironment.store
        switch store.selectedTab {
        case .home:
            if case .tradingRulesAnalytics = store.paths.home.last { return true }
        case .feed:
            if case .tradingRulesAnalytics = store.paths.feed.last { return true }
        case .messages:
            if case .tradingRulesAnalytics = store.paths.messages.last { return true }
        case .profile:
            if case .tradingRulesAnalytics = store.paths.profile.last { return true }
        case .create:
            break
        }
        return false
    }

    private func refreshAnalytics(forceReveal: Bool) async {
        guard let profileID = activeProfileID else {
            rulesPresentationStore.reset()
            loadOutcome = .failed("Sign in to view trading rules analytics.")
            return
        }

        if usesTraxsProPreviewDataPlane {
            await refreshTraxsProPreviewAnalytics(profileID: profileID, forceReveal: forceReveal)
            return
        }

        let accounts = await loadAccountsForScope(profileID: profileID)
        scopeController.hydrate(profileID: profileID, accounts: accounts)

        loadGeneration += 1
        let generation = loadGeneration

        if forceReveal {
            _ = TradingRulesCompliancePresentationBridge.revealCachedSnapshotIfPossible(
                profileID: profileID,
                detailCache: data.detailCache
            )
        }

        let hadSnapshot = rulesPresentationStore.ready && rulesPresentationStore.profileID == profileID
        isRefreshing = !hadSnapshot
        defer { isRefreshing = false }

        let outcome = await TradingRulesCompliancePresentationBridge.refresh(
            dependencies: loadDependencies
        )
        guard generation == loadGeneration else { return }
        loadOutcome = outcome
        presentationRevision = rulesPresentationStore.contentRevision
    }

    private func refreshTraxsProPreviewAnalytics(profileID: ProfileID, forceReveal: Bool) async {
        let accounts = TradingRulesAnalyticsPreviewSupport.previewAccounts(
            profileID: profileID,
            dependencies: loadDependencies
        )
        scopeController.hydrate(profileID: profileID, accounts: accounts)
        scopeController.applyTraxsProPreviewScopeDefaultsIfNeeded()

        loadGeneration += 1
        let generation = loadGeneration

        isRefreshing = !canShowDetailView
        defer { isRefreshing = false }

        if forceReveal, rulesPresentationStore.result != nil {
            presentationRevision = rulesPresentationStore.contentRevision
        }

        if let dashboard = TradingRulesCompliancePresentationBridge.dashboardViewModel,
           dashboard.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            RulesPreviewDebugLog.log("HomeRouteView refresh via dashboard recompute (preview plane)")
            await dashboard.ensureTradingRulesComplianceForPresentation(dependencies: loadDependencies)
        } else if rulesPresentationStore.result == nil || rulesPresentationStore.profileID != profileID {
            RulesPreviewDebugLog.log("HomeRouteView refresh seed bundled preview snapshot")
            TradingRulesAnalyticsPreviewSupport.seedActivePreviewEnvironmentRulesPresentation()
            if rulesPresentationStore.result == nil {
                let generation = TraxsProPreviewSession.shared.activePreviewEnvironment?.generation ?? 0
                _ = TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshotSynchronously(
                    profileID: profileID,
                    presentationStore: rulesPresentationStore,
                    preferenceContext: TradingRulesAnalyticsPreviewSupport.resolvedPreferenceContext(for: profileID),
                    accounts: accounts,
                    ownerTrades: TradingRulesAnalyticsPreviewSupport.previewOwnerTrades(profileID: profileID),
                    generation: generation,
                    dashboardScopeFilter: scopeController.clientScopeFilter()
                )
            }
        }

        guard generation == loadGeneration else { return }
        loadOutcome = .ready
        presentationRevision = rulesPresentationStore.contentRevision
        scopeController.syncFromDashboardIfAvailable()
        RulesPreviewDebugLog.log(
            "HomeRouteView refreshTraxsProPreview done \(RulesPreviewDebugLog.describe(session: rulesPresentationStore))"
        )
    }

    private func republishPreviewRulesForCurrentScope() {
        guard let profileID = activeProfileID else { return }
        guard usesTraxsProPreviewDataPlane else { return }
        if let dashboard = TradingRulesCompliancePresentationBridge.dashboardViewModel,
           dashboard.isTradingRulesComplianceDashboardSource(profileID: profileID)
        {
            dashboard.applyClientScopeFromAnalytics(scopeController.clientScopeFilter())
            return
        }
        let accounts = TradingRulesAnalyticsPreviewSupport.previewAccounts(
            profileID: profileID,
            dependencies: loadDependencies
        )
        let generation = TraxsProPreviewSession.shared.activePreviewEnvironment?.generation ?? 0
        _ = TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshotSynchronously(
            profileID: profileID,
            presentationStore: rulesPresentationStore,
            preferenceContext: TradingRulesAnalyticsPreviewSupport.resolvedPreferenceContext(for: profileID),
            accounts: accounts,
            ownerTrades: TradingRulesAnalyticsPreviewSupport.previewOwnerTrades(profileID: profileID),
            generation: generation,
            dashboardScopeFilter: scopeController.clientScopeFilter()
        )
        presentationRevision = rulesPresentationStore.contentRevision
    }

    private func loadAccountsForScope(profileID: ProfileID) async -> [TradingAccount] {
        if usesTraxsProPreviewDataPlane {
            return TradingRulesAnalyticsPreviewSupport.previewAccounts(
                profileID: profileID,
                dependencies: loadDependencies
            )
        }
        if let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty {
            return cached
        }
        if let seeded = data.detailCache.accounts(for: profileID), !seeded.isEmpty {
            return seeded
        }
        do {
            return try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: data.detailCache,
                repository: data.trades,
                forceNetwork: false,
                viewerProfileID: profileID
            )
        } catch {
            return SessionAccountsStore.shared.cached(for: profileID) ?? []
        }
    }
}