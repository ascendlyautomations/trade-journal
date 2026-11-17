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

    var body: some View {
        Group {
            if snapshotMatchesActiveViewer {
                TradingRulesComplianceDetailView(
                    scopeController: scopeController,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    loadDependencies: loadDependencies,
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
            await refreshAnalytics(forceReveal: true)
        }
        .onAppear {
            guard didAppearOnce else {
                didAppearOnce = true
                return
            }
            Task { await refreshAnalytics(forceReveal: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingPreferencesDidChange)) { _ in
            if let profileID = activeProfileID {
                TradingRulesCompliancePreferencesCache.invalidate(profileID: profileID)
            }
            TradingRulesComplianceRecomputeCoordinator.reset()
            Task { await refreshAnalytics(forceReveal: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingRulesComplianceOwnerTradesChanged)) { notification in
            guard let profileID = activeProfileID,
                  let raw = notification.userInfo?["profileID"] as? String,
                  raw == profileID.rawValue
            else { return }
            Task { await refreshAnalytics(forceReveal: false) }
        }
    }

    /// Stable identity — must not include `contentRevision` (publish bumps would retrigger `.task` forever).
    private var taskIdentity: String {
        activeProfileID?.rawValue ?? "none"
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
        presentationRevision = TradingRulesComplianceSessionStore.shared.contentRevision
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
