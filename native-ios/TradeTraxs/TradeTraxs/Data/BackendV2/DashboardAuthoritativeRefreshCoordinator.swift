import Foundation

/// Logical sources for dashboard authoritative network refresh (dedup + tracing).
enum DashboardAuthoritativeRefreshTrigger: String, Sendable {
    case cold = "dashboard.cold"
    case staleAuthoritative = "dashboard.stale_authoritative"
    case displayOnlyRevalidate = "dashboard.display_only_revalidate"
    case viewerSync = "dashboard.viewer_sync"
    case pullRefresh = "dashboard.pull_refresh"
    case journalMutation = "dashboard.journal_mutation"

    var permitsLaunchDedup: Bool {
        switch self {
        case .pullRefresh, .journalMutation:
            return false
        default:
            return true
        }
    }
}

/// Coordinates equivalent dashboard authoritative refresh intents (VM, loader, viewer sync).
@MainActor
final class DashboardAuthoritativeRefreshCoordinator {
    static let shared = DashboardAuthoritativeRefreshCoordinator()

    struct SuccessRecord {
        var completedAt: Date
        var trigger: DashboardAuthoritativeRefreshTrigger
        var tradeHistoryComplete: Bool
        var totalTradeCount: Int?
    }

    private struct InFlightRecord {
        var trigger: DashboardAuthoritativeRefreshTrigger
        var task: Task<DashboardBootstrapLoadResult, Error>
    }

    private var inFlight: [String: InFlightRecord] = [:]
    private var lastNetworkSuccess: [String: SuccessRecord] = [:]

    private let recentSuccessWindow: TimeInterval = 8

    private init() {}

    func reset() {
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
        lastNetworkSuccess.removeAll()
    }

    func hasInFlight(viewerID: ProfileID) -> Bool {
        inFlight[viewerID.rawValue] != nil
    }

    func awaitInFlightIfNeeded(viewerID: ProfileID) async {
        guard let record = inFlight[viewerID.rawValue] else { return }
        _ = try? await record.task.value
    }

    func shouldSkipViewerSyncDashboardLoad(viewerID: ProfileID) -> Bool {
        let uid = viewerID.rawValue
        if inFlight[uid] != nil { return false }
        guard let last = lastNetworkSuccess[uid], last.trigger.permitsLaunchDedup else { return false }
        return Date().timeIntervalSince(last.completedAt) <= recentSuccessWindow
    }

    func recordAppliedNetworkResult(
        viewerID: ProfileID,
        trigger: DashboardAuthoritativeRefreshTrigger,
        applied: DashboardBootstrapApplier.Applied,
        rpcRequestCount: Int
    ) {
        guard rpcRequestCount > 0 else { return }
        lastNetworkSuccess[viewerID.rawValue] = SuccessRecord(
            completedAt: Date(),
            trigger: trigger,
            tradeHistoryComplete: applied.tradeHistoryComplete,
            totalTradeCount: applied.totalTradeCount
        )
    }

    func lastSuccessfulNetworkRefresh(viewerID: ProfileID) -> SuccessRecord? {
        lastNetworkSuccess[viewerID.rawValue]
    }

    func scheduleAuthoritativeRefresh(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        trigger: DashboardAuthoritativeRefreshTrigger,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) {
        Task(priority: .userInitiated) { @MainActor in
            _ = try? await loadAuthoritative(
                viewerID: viewerID,
                rpc: rpc,
                detailCache: detailCache,
                forceNetwork: true,
                trigger: trigger,
                loadGeneration: loadGeneration,
                currentGeneration: currentGeneration,
                skipSoftStaleReconcile: true
            )
        }
    }

    func loadAuthoritative(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        forceNetwork: Bool,
        trigger: DashboardAuthoritativeRefreshTrigger,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64,
        skipSoftStaleReconcile: Bool = false
    ) async throws -> DashboardBootstrapLoadResult {
        _ = skipSoftStaleReconcile
        let uid = viewerID.rawValue

        if forceNetwork, trigger.permitsLaunchDedup, let existing = inFlight[uid] {
            #if DEBUG
            let intentID = BootstrapRpcTrace.beginIntent(
                rpc: BackendV2Versioning.RPCName.dashboard.rawValue,
                trigger: trigger.rawValue,
                forceNetwork: true
            )
            BootstrapRpcTrace.recordSingleFlightJoin(
                intentID: intentID,
                rpc: BackendV2Versioning.RPCName.dashboard.rawValue,
                joinedExisting: true,
                waiterCount: 1
            )
            #endif
            return try await existing.task.value
        }

        if forceNetwork,
           trigger == .viewerSync,
           shouldSkipViewerSyncDashboardLoad(viewerID: viewerID)
        {
            #if DEBUG
            let intentID = BootstrapRpcTrace.beginIntent(
                rpc: BackendV2Versioning.RPCName.dashboard.rawValue,
                trigger: trigger.rawValue,
                forceNetwork: true
            )
            BootstrapRpcTrace.recordSkippedDuplicate(
                intentID: intentID,
                rpc: BackendV2Versioning.RPCName.dashboard.rawValue,
                trigger: trigger.rawValue,
                reason: "recent_authoritative_success"
            )
            #endif
            if let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: uid) {
                let applied = try await DashboardBootstrapApplier.apply(
                    cached.bootstrap,
                    expectedViewerID: uid,
                    detailCache: detailCache
                )
                return DashboardBootstrapLoadResult(
                    applied: applied,
                    path: .cache_fresh,
                    rpcRequestCount: 0
                )
            }
            throw CancellationError()
        }

        let runNetwork = { () async throws -> DashboardBootstrapLoadResult in
            try await DashboardBootstrapLoader.loadFromNetwork(
                viewerID: viewerID,
                rpc: rpc,
                detailCache: detailCache,
                trigger: trigger,
                loadGeneration: loadGeneration,
                currentGeneration: currentGeneration
            )
        }

        let result: DashboardBootstrapLoadResult
        if forceNetwork, trigger.permitsLaunchDedup {
            let task = Task { @MainActor in try await runNetwork() }
            inFlight[uid] = InFlightRecord(trigger: trigger, task: task)
            defer { inFlight.removeValue(forKey: uid) }
            result = try await task.value
        } else {
            result = try await runNetwork()
        }

        recordAppliedNetworkResult(
            viewerID: viewerID,
            trigger: trigger,
            applied: result.applied,
            rpcRequestCount: result.rpcRequestCount
        )
        return result
    }
}
