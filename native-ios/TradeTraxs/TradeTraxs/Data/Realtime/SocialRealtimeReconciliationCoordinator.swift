import Foundation

nonisolated enum SocialRealtimeRepairReason: String, Sendable {
    case realtimeReconnect
    case networkRegain
}

/// Bounded missed-event repair after Realtime disconnect — orchestrates existing owners only.
actor SocialRealtimeReconciliationCoordinator {
    static let shared = SocialRealtimeReconciliationCoordinator()

    private var viewerID: ProfileID?
    private var viewerGeneration: UInt64 = 0
    private var disconnectObservedAt: Date?
    private var lastSuccessfulRepairAt: Date?
    private var repairTask: Task<Void, Never>?
    private var pendingReasons: Set<SocialRealtimeRepairReason> = []

    /// Suppress duplicate repair bursts immediately after a successful cycle (not polling).
    private static let postRepairSuppression: TimeInterval = 3

    private init() {}

    func bindViewer(_ viewerID: ProfileID) {
        guard SocialRealtimeRepairGate.isEnabled else { return }
        if self.viewerID != viewerID {
            viewerGeneration &+= 1
        }
        self.viewerID = viewerID
    }

    func reset() {
        viewerGeneration &+= 1
        viewerID = nil
        disconnectObservedAt = nil
        lastSuccessfulRepairAt = nil
        repairTask?.cancel()
        repairTask = nil
        pendingReasons = []
        Task { @MainActor in
            SocialRealtimeRepairSurfaces.shared.clearSession()
        }
    }

    func noteDisconnectObserved(activeRoutes: Int = 0) {
        guard SocialRealtimeRepairGate.isEnabled else { return }
        disconnectObservedAt = Date()
#if DEBUG
        SocialRealtimeRepairDebugLog.disconnectObserved(activeRoutes: activeRoutes)
#endif
    }

    func noteReconnectCompleted(activeRoutes: Int = 0) {
        guard SocialRealtimeRepairGate.isEnabled else { return }
#if DEBUG
        SocialRealtimeRepairDebugLog.reconnectObserved(activeRoutes: activeRoutes)
#endif
    }

    func requestRepair(_ reason: SocialRealtimeRepairReason) {
        guard SocialRealtimeRepairGate.isEnabled else { return }
        guard viewerID != nil else { return }
        Task {
            await SupabaseReconnectRepairCoordinator.shared.enqueueRepair(
                reason == .networkRegain ? .networkRegain : .realtimeReconnect
            )
        }
    }

    /// Single coalesced social repair cycle — invoked by ``SupabaseReconnectRepairCoordinator`` only.
    func performCoalescedRepair(reasons: Set<SocialRealtimeRepairReason>) async {
        guard SocialRealtimeRepairGate.isEnabled else { return }
        guard let viewer = viewerID else { return }

        if reasons.contains(.networkRegain), disconnectObservedAt == nil {
#if DEBUG
            SocialRealtimeRepairDebugLog.domainSkippedFresh(domain: "all", detail: "network_regain_without_disconnect")
#endif
            if !reasons.contains(.realtimeReconnect) {
                return
            }
        }

        if repairTask != nil {
            SupabasePressureLog.repairCoalesced(domain: "social", detail: "repair_task_active")
            pendingReasons.formUnion(reasons)
            return
        }

        if shouldSuppressImmediatelyAfterSuccess() {
#if DEBUG
            SocialRealtimeRepairDebugLog.domainSkippedFresh(domain: "all", detail: "post_repair_suppression")
#endif
            return
        }

        let generation = viewerGeneration
        let gapStart = disconnectObservedAt
#if DEBUG
        SocialRealtimeRepairDebugLog.repairStarted(
            reasons: reasons.map(\.rawValue).sorted().joined(separator: ","),
            viewerGeneration: generation
        )
#endif
        await SocialRealtimeRepairExecutor.shared.performRepair(
            viewerID: viewer,
            viewerGeneration: generation,
            reasons: reasons,
            disconnectObservedAt: gapStart
        )
        guard generation == viewerGeneration, viewerID == viewer else { return }
        lastSuccessfulRepairAt = Date()
        disconnectObservedAt = nil
    }

    func snapshotForTesting() -> (viewerID: ProfileID?, generation: UInt64, pending: Set<SocialRealtimeRepairReason>) {
        (viewerID, viewerGeneration, pendingReasons)
    }

    func awaitIdleForTesting(timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if repairTask == nil, pendingReasons.isEmpty {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testing_forceRepairCycle() async {
        guard let viewer = viewerID else { return }
        let generation = viewerGeneration
        await SocialRealtimeRepairExecutor.shared.performRepair(
            viewerID: viewer,
            viewerGeneration: generation,
            reasons: [.realtimeReconnect],
            disconnectObservedAt: disconnectObservedAt
        )
    }

    private func shouldSuppressImmediatelyAfterSuccess() -> Bool {
        guard let lastSuccessfulRepairAt else { return false }
        return Date().timeIntervalSince(lastSuccessfulRepairAt) < Self.postRepairSuppression
    }

    private func scheduleRepairIfNeeded() {
        guard repairTask == nil else { return }
        repairTask = Task { [weak self] in
            guard let self else { return }
            await self.runRepairLoop()
        }
    }

    private func runRepairLoop() async {
        defer { repairTask = nil }
        repeat {
            guard !pendingReasons.isEmpty else { return }
            let reasons = pendingReasons
            pendingReasons = []
            let generation = viewerGeneration
            guard let viewer = viewerID else { return }
            let gapStart = disconnectObservedAt
#if DEBUG
            SocialRealtimeRepairDebugLog.repairStarted(
                reasons: reasons.map(\.rawValue).sorted().joined(separator: ","),
                viewerGeneration: generation
            )
#endif
            await SocialRealtimeRepairExecutor.shared.performRepair(
                viewerID: viewer,
                viewerGeneration: generation,
                reasons: reasons,
                disconnectObservedAt: gapStart
            )
            guard generation == viewerGeneration, viewerID == viewer else {
#if DEBUG
                SocialRealtimeRepairDebugLog.staleGenerationRejected(context: "post_repair")
#endif
                return
            }
            lastSuccessfulRepairAt = Date()
            disconnectObservedAt = nil
        } while !pendingReasons.isEmpty
    }
}

/// MainActor repair side effects against canonical stores (non-destructive on failure).
@MainActor
final class SocialRealtimeRepairExecutor {
    static let shared = SocialRealtimeRepairExecutor()

    private weak var dataEnvironment: DataEnvironment?

    private init() {}

    func configure(data: DataEnvironment) {
        dataEnvironment = data
    }

    func performRepair(
        viewerID: ProfileID,
        viewerGeneration: UInt64,
        reasons: Set<SocialRealtimeRepairReason>,
        disconnectObservedAt: Date?
    ) async {
        guard SocialRealtimeRepairGate.isEnabled else { return }
        let started = Date()
        var requestCount = 0
        var repairedDomains: [String] = []
        var activityMerged: Int?
        var inboxChanged: Bool?

        let meaningfulGap = disconnectObservedAt != nil
            || reasons.contains(.realtimeReconnect)

        if await repairActivity(viewerID: viewerID, generation: viewerGeneration, meaningfulGap: meaningfulGap) {
            requestCount += 1
            repairedDomains.append("activity")
            activityMerged = ActivityInboxStore.shared.items.count
        }

        if await repairMessaging(viewerID: viewerID, generation: viewerGeneration, meaningfulGap: meaningfulGap) {
            requestCount += 1
            repairedDomains.append("messaging")
            inboxChanged = true
        }

        if await repairOpenThreads(generation: viewerGeneration) {
            requestCount += 1
            repairedDomains.append("openThread")
        }

        _ = reasons
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
#if DEBUG
        SocialRealtimeRepairDebugLog.repairCompleted(
            elapsedMs: elapsedMs,
            requestCount: requestCount,
            domains: repairedDomains.joined(separator: ","),
            feedDelta: nil,
            activityMerged: activityMerged,
            inboxChanged: inboxChanged,
            followingDelta: nil
        )
#endif
    }

    private func repairActivity(
        viewerID: ProfileID,
        generation: UInt64,
        meaningfulGap: Bool
    ) async -> Bool {
        let store = ActivityInboxStore.shared
        guard store.hasBootstrappedUnread || store.hasLoaded else {
#if DEBUG
            SocialRealtimeRepairDebugLog.domainSkippedFresh(domain: "activity", detail: "not_bootstrapped")
#endif
            return false
        }
        if store.hasLoaded {
            if !meaningfulGap,
               let last = store.lastLoadedAt,
               Date().timeIntervalSince(last) < MessagingInboxFreshness.softStaleSeconds
            {
#if DEBUG
                SocialRealtimeRepairDebugLog.domainSkippedFresh(domain: "activity", detail: "fresh")
#endif
                return false
            }
        }
        guard let data = dataEnvironment else { return false }
        guard await data.session.currentUserID?.rawValue == viewerID.rawValue else {
#if DEBUG
            SocialRealtimeRepairDebugLog.staleGenerationRejected(context: "activity_viewer")
#endif
            return false
        }
#if DEBUG
        SocialRealtimeRepairDebugLog.domainRepairStarted(domain: "activity")
#endif
        if store.hasLoaded {
            let activityScreenActive = ActivityFeedBootstrapPriorityGate.prefersVisibleBootstrap
            if activityScreenActive || meaningfulGap {
#if DEBUG
                SupabaseEfficiencyProbe.activityReconnect(.full)
#endif
                await store.repairAfterReconnect(
                    viewerID: viewerID,
                    detailCache: data.detailCache,
                    rpc: data.rpc
                )
            } else {
#if DEBUG
                SupabaseEfficiencyProbe.activityReconnect(.unreadOnly)
#endif
                await store.repairUnreadAfterReconnect(
                    viewerID: viewerID,
                    notifications: data.notifications,
                    detailCache: data.detailCache,
                    rpc: data.rpc
                )
            }
        } else if store.hasBootstrappedUnread {
#if DEBUG
            SupabaseEfficiencyProbe.activityReconnect(.unreadOnly)
#endif
            await store.repairUnreadAfterReconnect(
                viewerID: viewerID,
                notifications: data.notifications,
                detailCache: data.detailCache,
                rpc: data.rpc
            )
        }
        return true
    }

    private func repairMessaging(
        viewerID: ProfileID,
        generation: UInt64,
        meaningfulGap: Bool
    ) async -> Bool {
        let inbox = MessagesInboxStore.shared
        guard inbox.hasLoaded else {
#if DEBUG
            SocialRealtimeRepairDebugLog.domainSkippedFresh(domain: "messaging", detail: "inbox_not_loaded")
#endif
            return false
        }
        if !meaningfulGap, !MessagingInboxFreshness.isSoftStale(lastLoadedAt: inbox.lastLoadedAt) {
#if DEBUG
            SocialRealtimeRepairDebugLog.domainSkippedFresh(domain: "messaging", detail: "inbox_fresh")
#endif
            return false
        }
#if DEBUG
        SocialRealtimeRepairDebugLog.domainRepairStarted(domain: "messaging")
#endif
        await MessagingDomain.shared.repairInboxAfterReconnect(expectedViewerGeneration: generation)
        return true
    }

    private func repairOpenThreads(generation: UInt64) async -> Bool {
        var ran = false
        if let repairConversation = SocialRealtimeRepairSurfaces.shared.repairOpenConversation {
            ran = true
#if DEBUG
            SocialRealtimeRepairDebugLog.domainRepairStarted(domain: "dmThread")
#endif
            await repairConversation()
        }
        if let repairRoom = SocialRealtimeRepairSurfaces.shared.repairOpenRoom {
            ran = true
#if DEBUG
            SocialRealtimeRepairDebugLog.domainRepairStarted(domain: "roomThread")
#endif
            await repairRoom()
        }
        _ = generation
        return ran
    }
}
