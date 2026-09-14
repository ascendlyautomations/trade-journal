import Foundation

struct ViewerSyncReconcileContext {
    var viewerID: ProfileID
    var rpc: any RPCClient
    var profiles: (any ProfileRepository)?
    var detailCache: DetailPresentationCache?
    var loadGeneration: UInt64
    var currentGeneration: () -> UInt64
    var needsSessionRefresh: Bool
    var needsDashboardRefresh: Bool
}

/// Single owner of soft-stale cache reconciliation — replaces parallel full bootstrap revalidation.
@MainActor
final class ViewerSyncReconciliationCoordinator {
    static let shared = ViewerSyncReconciliationCoordinator()

    private var reconcileTask: Task<Void, Never>?
    private var pending: ViewerSyncReconcileContext?

    private init() {}

    func schedule(_ context: ViewerSyncReconcileContext) {
        pending = merge(pending, context)
        guard reconcileTask == nil else { return }
        reconcileTask = Task { @MainActor in
            defer { reconcileTask = nil }
            repeat {
                guard let ctx = pending else { break }
                pending = nil
                await reconcile(ctx)
            } while pending != nil
        }
    }

    func reset() {
        reconcileTask?.cancel()
        reconcileTask = nil
        pending = nil
    }

    #if DEBUG
    func awaitIdleForTesting(timeoutNanoseconds: UInt64 = 2_000_000_000) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while reconcileTask != nil, DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    #endif

    private func merge(_ a: ViewerSyncReconcileContext?, _ b: ViewerSyncReconcileContext) -> ViewerSyncReconcileContext {
        guard let a else { return b }
        var merged = a
        merged.needsSessionRefresh = a.needsSessionRefresh || b.needsSessionRefresh
        merged.needsDashboardRefresh = a.needsDashboardRefresh || b.needsDashboardRefresh
        if b.profiles != nil { merged.profiles = b.profiles }
        if b.detailCache != nil { merged.detailCache = b.detailCache }
        merged.loadGeneration = max(a.loadGeneration, b.loadGeneration)
        return merged
    }

    private func reconcile(_ context: ViewerSyncReconcileContext) async {
        guard context.currentGeneration() == context.loadGeneration else { return }

        let uid = context.viewerID.rawValue
        let rpcName = BackendV2Versioning.RPCName.viewerSyncState.rawValue

        guard BackendV2FeatureFlags.isEnabled(.session), BackendV2FeatureFlags.isEnabled(.dashboard) else {
            preserveStaleCache(context, reason: "flags_off")
            return
        }

        guard BackendV2FeatureFlags.isEnabled(.viewerSyncState) else {
            preserveStaleCache(context, reason: "sync_flag_off")
            return
        }

        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: uid) {
            SyncStateProbe.logFallback("sync_rpc_unavailable")
            preserveStaleCache(context, reason: "sync_rpc_unavailable")
            return
        }

        let hasSessionCache = BackendV2BootstrapDiskCache.loadSession(viewerID: uid) != nil
        let hasDashboardCache = BackendV2BootstrapDiskCache.loadDashboard(viewerID: uid) != nil
        guard hasSessionCache || hasDashboardCache else {
            SyncStateProbe.logFallback("no_usable_cache")
            return
        }

        do {
            let repo = ViewerSyncStateRepository(rpc: context.rpc)
            let encoded = try await ViewerSyncTransportTimeout.run {
                try await BackendV2SingleFlight.shared.coalesce(
                    key: BackendV2FlightKeys.viewerSyncState(viewerID: uid)
                ) {
                    let response = try await repo.loadSyncState()
                    return try JSONEncoder().encode(response)
                }
            }
            #if DEBUG
            SyncStateProbe.logResponseBytes(encoded.count)
            #endif

            guard context.currentGeneration() == context.loadGeneration else { return }

            let serverResponse = try JSONDecoder().decode(ViewerSyncStateV1.self, from: encoded)
            try serverResponse.validateContractVersion()
            guard serverResponse.meta.viewer_id == uid else { return }

            let serverFingerprints = serverResponse.fingerprints
            SyncStateProbe.logServer(serverFingerprints)

            let localFingerprints = ViewerSyncStateDiskCache.load(viewerID: uid)
            if let localFingerprints {
                SyncStateProbe.logLocal(localFingerprints)
            }

            let changed: [ViewerSyncDomain]
            if let localFingerprints {
                changed = localFingerprints.changedDomains(comparedTo: serverFingerprints)
            } else {
                // First reconcile after upgrade — establish baseline without full download.
                changed = []
                SyncStateProbe.logFallback("baseline_established")
            }

            if changed.isEmpty {
                BackendV2BootstrapDiskCache.touchSession(viewerID: uid)
                BackendV2BootstrapDiskCache.touchDashboard(viewerID: uid)
                ViewerSyncStateDiskCache.save(serverFingerprints)
                SyncStateProbe.logUnchanged(
                    dashboardBootstrapSkipped: context.needsDashboardRefresh,
                    sessionBootstrapSkipped: context.needsSessionRefresh
                )
                return
            }

            SyncStateProbe.logChanged(domains: changed, action: refreshAction(for: changed))

            let needsDashboard = changed.contains(.trades) || changed.contains(.accounts)
            let needsSession = changed.contains(.profile)

            if needsDashboard, let detailCache = context.detailCache {
                _ = try await DashboardBootstrapLoader.load(
                    viewerID: context.viewerID,
                    rpc: context.rpc,
                    detailCache: detailCache,
                    forceNetwork: true,
                    loadGeneration: context.loadGeneration,
                    currentGeneration: context.currentGeneration,
                    skipSoftStaleReconcile: true
                )
            }

            if needsSession, let profiles = ViewerSyncStateRuntime.resolvedProfiles(fallback: context.profiles) {
                _ = try await SessionBootstrapLoader.load(
                    viewerID: context.viewerID,
                    rpc: context.rpc,
                    profiles: profiles,
                    detailCache: context.detailCache,
                    forceNetwork: true,
                    loadGeneration: context.loadGeneration,
                    currentGeneration: context.currentGeneration,
                    skipSoftStaleReconcile: true
                )
            }

            await ViewerSyncStateCapturer.refreshFromServer(viewerID: uid, rpc: context.rpc)
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: uid)
                SyncStateProbe.logFallback("sync_rpc_unavailable")
                preserveStaleCache(context, reason: "sync_rpc_unavailable")
                return
            }
            // Network failure with usable cache — keep displaying cached data.
            SyncStateProbe.logFallback("sync_rpc_error_preserved_cache")
            preserveStaleCache(context, reason: "sync_rpc_error_preserved_cache")
        }
    }

    /// Stale-while-revalidate: keep cached UI interactive — never force full bootstrap on sync miss.
    private func preserveStaleCache(_ context: ViewerSyncReconcileContext, reason: String) {
        let uid = context.viewerID.rawValue
        BackendV2BootstrapDiskCache.touchSession(viewerID: uid)
        BackendV2BootstrapDiskCache.touchDashboard(viewerID: uid)
        SyncStateProbe.logUnchanged(
            dashboardBootstrapSkipped: context.needsDashboardRefresh,
            sessionBootstrapSkipped: context.needsSessionRefresh
        )
        if reason != "sync_rpc_unavailable", reason != "sync_rpc_error_preserved_cache" {
            SyncStateProbe.logFallback(reason)
        }
    }

    private func refreshAction(for domains: [ViewerSyncDomain]) -> String {
        if domains.contains(.trades) || domains.contains(.accounts) {
            return domains.contains(.profile) ? "refreshDashboard+session" : "refreshDashboard"
        }
        if domains.contains(.profile) {
            return "refreshSession"
        }
        return "none"
    }

}
