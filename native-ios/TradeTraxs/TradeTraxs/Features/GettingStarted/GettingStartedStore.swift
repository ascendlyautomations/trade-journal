import Foundation
import Observation

/// Session-scoped Getting Started checklist — one RPC, no polling.
@Observable
@MainActor
final class GettingStartedStore {
    static let shared = GettingStartedStore()

    private(set) var signals: GettingStartedSignals = .empty
    private(set) var progress: GettingStartedProgress = GettingStartedChecklistPolicy.computeProgress(from: .empty)
    private(set) var signalsReady = false
    private(set) var isRefreshing = false

    private var rpc: (any RPCClient)?
    private var session: (any SessionProviding)?
    private var realtimeHub: RealtimeHub?
    private var viewerID: ProfileID?
    private var refreshTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var pendingUserActionRefresh = false

    var isCollapsed = false

    private init() {}

    func configure(
        rpc: any RPCClient,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        self.rpc = rpc
        self.session = session
        self.realtimeHub = realtimeHub
    }

    var shouldShowDashboardCard: Bool {
        guard let viewerID else { return false }
        return GettingStartedChecklistPolicy.shouldShowDashboardCard(
            userID: viewerID.rawValue,
            signals: signals,
            progress: progress,
            sessionDismissed: GettingStartedPreferences.isSessionDismissed(userID: viewerID.rawValue)
        )
    }

    func loadIfNeeded() {
        guard BackendV2FeatureFlags.isEnabled(.gettingStarted) else { return }
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            await self?.performRefresh(fromUserAction: false)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    func refresh(fromUserAction: Bool = false) {
        guard BackendV2FeatureFlags.isEnabled(.gettingStarted) else { return }
        if fromUserAction {
            pendingUserActionRefresh = true
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(fromUserAction: fromUserAction)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    func invalidate() {
        refreshTask?.cancel()
        realtimeTask?.cancel()
        refreshTask = nil
        realtimeTask = nil
        signals = .empty
        progress = GettingStartedChecklistPolicy.computeProgress(from: .empty)
        signalsReady = false
        isRefreshing = false
        viewerID = nil
        loadGeneration &+= 1
        pendingUserActionRefresh = false
        isCollapsed = false
    }

    func dismissForSession() {
        guard let viewerID else { return }
        GettingStartedPreferences.markSessionDismissed(userID: viewerID.rawValue)
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
        guard let viewerID else { return }
        GettingStartedPreferences.writeCollapsed(userID: viewerID.rawValue, collapsed: isCollapsed)
    }

    func onForeground() {
        guard signalsReady, !progress.allComplete else { return }
        refresh(fromUserAction: false)
    }

    private func performRefresh(fromUserAction: Bool) async {
        guard let rpc, let session else { return }
        guard let userID = await session.currentUserID else { return }

        let profileID = ProfileID(userID.rawValue)
        if viewerID != profileID {
            viewerID = profileID
            isCollapsed = GettingStartedPreferences.readCollapsed(userID: profileID.rawValue)
            startRealtimeIfNeeded(viewerID: userID.rawValue)
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        if !fromUserAction {
            isRefreshing = !signalsReady
        }

        do {
            await SessionNetworkGate.shared.awaitReady()
            let loaded = try await GettingStartedLoader.load(viewerID: profileID, rpc: rpc)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            apply(signals: loaded)
        } catch GettingStartedLoader.LoaderError.flagOff,
                GettingStartedLoader.LoaderError.rpcUnavailable {
            // Hide checklist quietly when RPC is unavailable.
        } catch is CancellationError {
            // Preserve last known progress.
        } catch {
            // Preserve last known progress on transient failures.
        }

        pendingUserActionRefresh = false
        isRefreshing = false
    }

    private func apply(signals: GettingStartedSignals) {
        self.signals = signals
        progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        signalsReady = true
    }

    private func startRealtimeIfNeeded(viewerID: String) {
        guard let realtimeHub, progress.allComplete == false else { return }
        stopRealtime()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            let token = await self.session?.accessToken
            for await _ in realtimeHub.watchViewerProfile(userID: viewerID, accessToken: token) {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.refresh(fromUserAction: false)
                }
            }
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let viewerID = viewerID?.rawValue {
            Task { await realtimeHub?.stopWatchingViewerProfile(userID: viewerID) }
        }
    }
}

/// Device-local presentation preferences — not synchronized across platforms.
enum GettingStartedPreferences {
    private static let collapsedKeyBase = "tradetraxs_getting_started_collapsed_v1"
    private static let sessionDismissKeyBase = "tradetraxs_getting_started_dismissed_session_v1"

    static func readCollapsed(userID: String) -> Bool {
        UserDefaults.standard.bool(forKey: "\(collapsedKeyBase):\(userID)")
    }

    static func writeCollapsed(userID: String, collapsed: Bool) {
        let key = "\(collapsedKeyBase):\(userID)"
        if collapsed {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func isSessionDismissed(userID: String) -> Bool {
        UserDefaults.standard.bool(forKey: "\(sessionDismissKeyBase):\(userID)")
    }

    static func markSessionDismissed(userID: String) {
        UserDefaults.standard.set(true, forKey: "\(sessionDismissKeyBase):\(userID)")
    }

    static func clearSessionDismissed(userID: String) {
        UserDefaults.standard.removeObject(forKey: "\(sessionDismissKeyBase):\(userID)")
    }
}

/// Call after checklist-eligible native mutations succeed.
@MainActor
enum GettingStartedRefreshCenter {
    static func noteEligibleUserAction() {
        GettingStartedStore.shared.refresh(fromUserAction: true)
    }
}
