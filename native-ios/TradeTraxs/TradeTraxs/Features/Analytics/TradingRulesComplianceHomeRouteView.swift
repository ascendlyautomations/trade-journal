import SwiftUI

struct TradingRulesComplianceHomeRouteView: View {
    let navigationCoordinator: NavigationCoordinator
    let data: DataEnvironment

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
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: activeProfileID
        )
    }

    private var restrictsFullAnalytics: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictTradingRulesComplianceAnalytics(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: activeProfileID
        )
    }

    var body: some View {
        Group {
            if showsEntitlementVerification {
                TraxProEntitlementVerificationView(profileID: activeProfileID) {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            } else if snapshotMatchesActiveViewer {
                TradingRulesComplianceDetailView(
                    scopeController: scopeController,
                    scrollAnchor: scrollAnchor,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    loadDependencies: loadDependencies,
                    presentation: restrictsFullAnalytics ? .freeTierBasic : .fullAnalytics,
                    onRetry: { Task { await refreshAnalytics(forceReveal: false) } }
                )
                .id(presentationRevision)
                .overlay(alignment: .top) {
                    if isRefreshing {
                        ProgressView()
                            .padding(.top, ExperienceSpacing.md)
                    }
                }
            } else if isRefreshing {
                ProgressView("Loading trading rules analytics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .experienceScreenBackground()
            } else if case .failed(let message) = loadOutcome {
                ExperienceErrorState(
                    title: "Couldn't load trading rules analytics",
                    message: message,
                    onRetry: { Task { await refreshAnalytics(forceReveal: false) } }
                )
            } else {
                ProgressView("Loading trading rules analytics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .experienceScreenBackground()
            }
        }
        .task(id: taskIdentity) {
            guard !showsEntitlementVerification else { return }
            await refreshAnalytics(forceReveal: true)
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
            if let profileID = activeProfileID {
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

    /// Stable identity, must not include `contentRevision` (publish bumps would retrigger `.task` forever).
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

    private var snapshotMatchesActiveViewer: Bool {
        guard let activeProfileID else { return false }
        return TradingRulesComplianceSessionStore.shared.profileID == activeProfileID
            && TradingRulesComplianceSessionStore.shared.ready
    }

    private func refreshAnalytics(forceReveal: Bool) async {
        guard let profileID = activeProfileID else {
            TradingRulesComplianceSessionStore.shared.reset()
            loadOutcome = .failed("Sign in to view trading rules analytics.")
            return
        }

        let accounts = await loadAccountsForScope(profileID: profileID)
        scopeController.hydrate(profileID: profileID, accounts: accounts)
        if TraxsProPreviewSupport.isTradingRulesPreviewActive {
            scopeController.applyTraxsProPreviewScopeDefaultsIfNeeded()
        }

        loadGeneration += 1
        let generation = loadGeneration

        if forceReveal {
            _ = TradingRulesCompliancePresentationBridge.revealCachedSnapshotIfPossible(
                profileID: profileID,
                detailCache: data.detailCache
            )
            if snapshotMatchesActiveViewer {
                presentationRevision = TradingRulesComplianceSessionStore.shared.contentRevision
            }
        }

        let hadSnapshot = snapshotMatchesActiveViewer
        isRefreshing = !hadSnapshot
        defer { isRefreshing = false }

        let outcome = await TradingRulesCompliancePresentationBridge.refresh(
            dependencies: loadDependencies
        )
        guard generation == loadGeneration else { return }
        loadOutcome = outcome
        let nextRevision = TradingRulesComplianceSessionStore.shared.contentRevision
        if nextRevision != presentationRevision {
            presentationRevision = nextRevision
        }
        scopeController.syncFromDashboardIfAvailable()
    }

    private func loadAccountsForScope(profileID: ProfileID) async -> [TradingAccount] {
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