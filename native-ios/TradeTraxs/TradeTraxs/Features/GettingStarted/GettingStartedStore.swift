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
    private var viewerID: ProfileID?
    private var refreshTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var pendingUserActionRefresh = false
    /// Monotonic checklist hints applied before first RPC load or merged after refresh.
    private var pendingLocalPatches = GettingStartedLocalPatches.empty

    var isCollapsed = false

    /// Permanent dismiss (X) is allowed only when every checklist task is complete.
    var canPermanentlyDismiss: Bool {
        signalsReady && progress.allComplete
    }

    private init() {}

    func configure(
        rpc: any RPCClient,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        self.rpc = rpc
        self.session = session
        _ = realtimeHub
    }

    var shouldShowDashboardCard: Bool {
        guard signalsReady, let viewerID else { return false }
        return GettingStartedChecklistPolicy.shouldShowDashboardCard(
            userID: viewerID.rawValue,
            signals: signals,
            progress: progress,
            sessionDismissed: GettingStartedPreferences.isSessionDismissed(userID: viewerID.rawValue)
        )
    }

    func loadIfNeeded() {
        guard BackendV2FeatureFlags.isEnabled(.gettingStarted) else { return }
        guard !signalsReady else { return }
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
        refreshTask = nil
        signals = .empty
        progress = GettingStartedChecklistPolicy.computeProgress(from: .empty)
        signalsReady = false
        isRefreshing = false
        viewerID = nil
        loadGeneration &+= 1
        pendingUserActionRefresh = false
        pendingLocalPatches = .empty
        isCollapsed = false
    }

    /// Apply monotonic checklist signal updates immediately (no RPC).
    func patchSignals(_ patch: GettingStartedLocalPatches) {
        guard BackendV2FeatureFlags.isEnabled(.gettingStarted) else { return }
        pendingLocalPatches.merge(patch)
        guard signalsReady else { return }
        let merged = pendingLocalPatches.apply(to: signals)
        pendingLocalPatches = .empty
        guard merged != signals else { return }
        signals = merged
        progress = GettingStartedChecklistPolicy.computeProgress(from: merged)
        reconcileServerCompletionIfNeeded()
    }

    func dismissForSession() {
        guard canPermanentlyDismiss, let viewerID else { return }
        GettingStartedPreferences.markSessionDismissed(userID: viewerID.rawValue)
        guard let rpc else { return }
        Task {
            let ok = await GettingStartedCompletionMarker.markSeenIfNeeded(rpc: rpc)
            guard ok else { return }
            await MainActor.run {
                guard self.viewerID?.rawValue == viewerID.rawValue else { return }
                var updated = self.signals
                updated.hasSeenOnboardingCompletePopup = true
                self.signals = updated
            }
        }
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

    private func apply(signals loaded: GettingStartedSignals) {
        let merged = pendingLocalPatches.apply(to: loaded)
        pendingLocalPatches = .empty
        signals = merged
        progress = GettingStartedChecklistPolicy.computeProgress(from: merged)
        signalsReady = true
        reconcileServerCompletionIfNeeded()
    }

    private func reconcileServerCompletionIfNeeded() {
        guard GettingStartedChecklistPolicy.needsServerCompletionReconciliation(
            signals: signals,
            progress: progress
        ), let rpc else { return }
        Task {
            let ok = await GettingStartedCompletionMarker.markSeenIfNeeded(rpc: rpc)
            guard ok else { return }
            await MainActor.run {
                guard GettingStartedChecklistPolicy.needsServerCompletionReconciliation(
                    signals: self.signals,
                    progress: self.progress
                ) else { return }
                var updated = self.signals
                updated.hasSeenOnboardingCompletePopup = true
                self.signals = updated
            }
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

/// Monotonic local checklist hints — merged with RPC/bootstrap (never regress).
struct GettingStartedLocalPatches: Sendable, Equatable {
    var onboardingCompleted: Bool?
    var tradeCountDelta: Int = 0
    var profilePostCountDelta: Int = 0
    var markFollowed: Bool = false
    var markJoinedOtherRoom: Bool = false
    var markPublicTrade: Bool = false
    var markDailyCheckInCompleted: Bool = false

    static let empty = GettingStartedLocalPatches()

    mutating func merge(_ other: GettingStartedLocalPatches) {
        if other.onboardingCompleted == true { onboardingCompleted = true }
        tradeCountDelta += other.tradeCountDelta
        profilePostCountDelta += other.profilePostCountDelta
        if other.markFollowed { markFollowed = true }
        if other.markJoinedOtherRoom { markJoinedOtherRoom = true }
        if other.markPublicTrade { markPublicTrade = true }
        if other.markDailyCheckInCompleted { markDailyCheckInCompleted = true }
    }

    func apply(to base: GettingStartedSignals) -> GettingStartedSignals {
        var next = base
        if onboardingCompleted == true { next.onboardingCompleted = true }
        if tradeCountDelta > 0 {
            next.tradeCount = max(next.tradeCount, next.tradeCount + tradeCountDelta)
        }
        if profilePostCountDelta > 0 {
            next.profilePostCount = max(next.profilePostCount, next.profilePostCount + profilePostCountDelta)
        }
        if markFollowed {
            next.followCount = max(next.followCount, 1)
        }
        if markJoinedOtherRoom {
            next.hasEverJoinedOtherRoom = true
        }
        if markPublicTrade {
            next.hasPublicTrade = true
        }
        if markDailyCheckInCompleted {
            next.hasCompletedDailyCheckIn = true
        }
        return next
    }
}

/// Call after checklist-eligible native mutations succeed.
@MainActor
enum GettingStartedRefreshCenter {
    static func noteProfileOnboardingCompleted() {
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(onboardingCompleted: true)
        )
    }

    static func noteTradePersisted(_ trade: Trade) {
        var patch = GettingStartedLocalPatches(tradeCountDelta: 1)
        if trade.visibility == .public {
            patch.markPublicTrade = true
        }
        GettingStartedStore.shared.patchSignals(patch)
    }

    static func noteTradesBulkPersisted(count: Int) {
        guard count > 0 else { return }
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(tradeCountDelta: count)
        )
    }

    static func noteTradeVisibilityUpdated(_ trade: Trade, previous: Trade?) {
        guard trade.visibility == .public else { return }
        if previous?.visibility == .public { return }
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(markPublicTrade: true)
        )
    }

    static func noteFollowSucceeded(viewer: ProfileID, target: ProfileID) {
        guard viewer != target else { return }
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(markFollowed: true)
        )
    }

    static func noteJoinedOtherTradeRoom(
        viewer: ProfileID,
        roomOwnerProfileID: ProfileID?,
        isViewerRoomOwner: Bool
    ) {
        guard GettingStartedRoomJoinEligibility.isJoiningOtherRoom(
            viewer: viewer,
            roomOwnerProfileID: roomOwnerProfileID,
            isViewerRoomOwner: isViewerRoomOwner
        ) else { return }
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(markJoinedOtherRoom: true)
        )
    }

    static func noteJoinedOtherTradeRoom(from room: ExploreRoomSuggestion, viewer: ProfileID) {
        noteJoinedOtherTradeRoom(
            viewer: viewer,
            roomOwnerProfileID: room.ownerProfileID,
            isViewerRoomOwner: room.isOwner == true
        )
    }

    static func noteProfilePostCreated() {
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(profilePostCountDelta: 1)
        )
    }

    static func noteDailyCheckInCompleted() {
        GettingStartedStore.shared.patchSignals(
            GettingStartedLocalPatches(markDailyCheckInCompleted: true)
        )
    }

    /// Debounced RPC reconcile — not used for instant UI.
    static func noteEligibleUserAction() {
        scheduleDebouncedReconcile()
    }

    private static var reconcileTask: Task<Void, Never>?

    private static func scheduleDebouncedReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            GettingStartedStore.shared.refresh(fromUserAction: true)
        }
    }
}

enum GettingStartedRoomJoinEligibility {
    static func isJoiningOtherRoom(
        viewer: ProfileID,
        roomOwnerProfileID: ProfileID?,
        isViewerRoomOwner: Bool
    ) -> Bool {
        if isViewerRoomOwner { return false }
        if let roomOwnerProfileID, roomOwnerProfileID == viewer { return false }
        return true
    }
}
