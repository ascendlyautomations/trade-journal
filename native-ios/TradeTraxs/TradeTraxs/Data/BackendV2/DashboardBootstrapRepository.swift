import Foundation
import os

/// Dashboard V2 bootstrap — `rpc_v1_dashboard_bootstrap`.
nonisolated struct DashboardRpcBootstrapRepository: DashboardBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadDashboardBootstrap(accountID: String?) async throws -> DashboardBootstrapV1 {
        let args = DashboardRpcArguments(
            p_account_id: accountID,
            p_trade_limit: DashboardBootstrapTradeLimit.default
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .dashboard,
            argumentsJSON: body,
            as: DashboardBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.dashboard.dottedName
            )
        )
        try value.validateContractVersion()
        try value.validateContract()
        return value
    }
}

/// Recent trade window shipped in dashboard bootstrap — metrics/equity use full scoped history server-side.
nonisolated enum DashboardBootstrapTradeLimit {
    static let `default` = 120
}

private nonisolated struct DashboardRpcArguments: Encodable, Sendable {
    var p_account_id: String?
    var p_trade_limit: Int
}

nonisolated enum BackendV2BootstrapPath: String, Sendable {
    case v2_rpc
    case legacy_flag_off
    case legacy_missing_rpc
    case cache_fresh
    case cache_stale_revalidate
    case cache_display_only
    case error_preserved_cache
}

struct DashboardBootstrapLoadResult: Sendable {
    var applied: DashboardBootstrapApplier.Applied
    var path: BackendV2BootstrapPath
    var rpcRequestCount: Int
}

enum DashboardBootstrapLoader {
    private static let rpcName = BackendV2Versioning.RPCName.dashboard.rawValue
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "BackendV2.Dashboard"
    )

    /// Flag ON entry — one RPC or cache; legacy only on confirmed missing RPC.
    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        forceNetwork: Bool,
        trigger: DashboardAuthoritativeRefreshTrigger = .cold,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64,
        skipSoftStaleReconcile: Bool = false
    ) async throws -> DashboardBootstrapLoadResult {
        guard BackendV2FeatureFlags.isEnabled(.dashboard) else {
            throw DashboardBootstrapLoaderError.flagOff
        }

        let uid = viewerID.rawValue

        if !forceNetwork, let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: uid) {
            let applied = try await DashboardBootstrapApplier.apply(
                cached.bootstrap,
                expectedViewerID: uid,
                detailCache: detailCache
            )
            let path = bootstrapPath(for: cached.freshness)
            logPath(path)
            if cached.freshness == .softStale, !forceNetwork, !skipSoftStaleReconcile {
                scheduleSoftStaleReconcile(
                    viewerID: viewerID,
                    rpc: rpc,
                    detailCache: detailCache,
                    loadGeneration: loadGeneration,
                    currentGeneration: currentGeneration
                )
            }
            if cached.freshness == .displayOnly, !forceNetwork {
                DashboardAuthoritativeRefreshCoordinator.shared.scheduleAuthoritativeRefresh(
                    viewerID: viewerID,
                    rpc: rpc,
                    detailCache: detailCache,
                    trigger: .displayOnlyRevalidate,
                    loadGeneration: loadGeneration,
                    currentGeneration: currentGeneration
                )
            }
            return DashboardBootstrapLoadResult(
                applied: applied,
                path: path,
                rpcRequestCount: 0
            )
        }

        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: uid) {
            throw DashboardBootstrapLoaderError.rpcUnavailable
        }

        return try await DashboardAuthoritativeRefreshCoordinator.shared.loadAuthoritative(
            viewerID: viewerID,
            rpc: rpc,
            detailCache: detailCache,
            forceNetwork: forceNetwork,
            trigger: trigger,
            loadGeneration: loadGeneration,
            currentGeneration: currentGeneration,
            skipSoftStaleReconcile: skipSoftStaleReconcile
        )
    }

    /// Authoritative network fetch + apply — invoked only via ``DashboardAuthoritativeRefreshCoordinator``.
    @MainActor
    static func loadFromNetwork(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        trigger: DashboardAuthoritativeRefreshTrigger,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) async throws -> DashboardBootstrapLoadResult {
        let uid = viewerID.rawValue
        let accountScope = "all"

        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: uid) {
            throw DashboardBootstrapLoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.dashboard(viewerID: uid, accountID: nil)
        do {
            let bootstrap = try await fetchRPC(
                viewerID: uid,
                rpc: rpc,
                flightKey: flightKey,
                trigger: trigger
            )
            guard currentGeneration() == loadGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            let applied = try await DashboardBootstrapApplier.apply(
                bootstrap,
                expectedViewerID: uid,
                detailCache: detailCache
            )
            logStage("state.apply.completed", detail: "trades=\(applied.trades.count) skipped=\(applied.skippedTrades)")
            logStage("cache.write.started")
            BackendV2BootstrapDiskCache.saveDashboard(bootstrap, viewerID: uid, accountScope: accountScope)
            logStage("cache.write.completed")
            ViewerSyncStateCapturer.captureAfterBootstrap(viewerID: uid, rpc: rpc)
            logPath(.v2_rpc)
            return DashboardBootstrapLoadResult(
                applied: applied,
                path: .v2_rpc,
                rpcRequestCount: 1
            )
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: uid)
                throw DashboardBootstrapLoaderError.rpcUnavailable
            }
            if let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: uid) {
                let applied = try await DashboardBootstrapApplier.apply(
                    cached.bootstrap,
                    expectedViewerID: uid,
                    detailCache: detailCache
                )
                logPath(.error_preserved_cache)
                return DashboardBootstrapLoadResult(
                    applied: applied,
                    path: .error_preserved_cache,
                    rpcRequestCount: 0
                )
            }
            throw error
        }
    }

    @MainActor
    private static func scheduleSoftStaleReconcile(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) {
        guard BackendV2FeatureFlags.isEnabled(.viewerSyncState) else {
            BackendV2BootstrapDiskCache.touchDashboard(viewerID: viewerID.rawValue)
            SyncStateProbe.logFallback("sync_flag_off_touch_dashboard")
            return
        }
        ViewerSyncReconciliationCoordinator.shared.schedule(
            ViewerSyncReconcileContext(
                viewerID: viewerID,
                rpc: rpc,
                profiles: nil,
                detailCache: detailCache,
                loadGeneration: loadGeneration,
                currentGeneration: currentGeneration,
                needsSessionRefresh: false,
                needsDashboardRefresh: true
            )
        )
    }

    private static func fetchRPC(
        viewerID: String,
        rpc: any RPCClient,
        flightKey: String,
        trigger: DashboardAuthoritativeRefreshTrigger
    ) async throws -> DashboardBootstrapV1 {
        let intentID = BootstrapRpcTrace.beginIntent(
            rpc: rpcName,
            trigger: trigger.rawValue,
            forceNetwork: true
        )
        let joinedExisting = await BackendV2SingleFlight.shared.hasInFlight(key: flightKey)
        let waiterCount = await BackendV2SingleFlight.shared.inFlightWaiterCount(key: flightKey)
        BootstrapRpcTrace.recordSingleFlightJoin(
            intentID: intentID,
            rpc: rpcName,
            joinedExisting: joinedExisting,
            waiterCount: waiterCount + (joinedExisting ? 1 : 0)
        )
        let httpRequestID = UUID()
        let httpStarted = CFAbsoluteTimeGetCurrent()
        BootstrapRpcTrace.httpWillStart(intentID: intentID, requestID: httpRequestID, rpc: rpcName)
        let repo = DashboardRpcBootstrapRepository(rpc: rpc)
        let data = try await BootstrapRpcTrace.runWithIntent(
            intentID: intentID,
            trigger: trigger.rawValue,
            rpc: rpcName
        ) {
            try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let bootstrap = try await repo.loadDashboardBootstrap(accountID: nil)
                let encoded = try JSONEncoder().encode(bootstrap)
                return encoded
            }
        }
        BootstrapRpcTrace.httpCompleted(
            intentID: intentID,
            requestID: httpRequestID,
            rpc: rpcName,
            elapsedMs: (CFAbsoluteTimeGetCurrent() - httpStarted) * 1000
        )
        let bootstrap = try JSONDecoder().decode(DashboardBootstrapV1.self, from: data)
        try bootstrap.validateContract()
        logStage("contract.validation.completed")
        return bootstrap
    }

    private static func logStage(_ stage: String, detail: String? = nil) {
        #if DEBUG
        logger.debug("dashboard bootstrap \(stage, privacy: .public)\(detail.map { " \($0)" } ?? "", privacy: .public)")
        #endif
    }

    private static func bootstrapPath(for freshness: BackendV2BootstrapDiskCache.Freshness) -> BackendV2BootstrapPath {
        switch freshness {
        case .fresh:
            return .cache_fresh
        case .softStale:
            return .cache_stale_revalidate
        case .displayOnly:
            return .cache_display_only
        case .expired:
            return .error_preserved_cache
        }
    }

    private static func logPath(_ path: BackendV2BootstrapPath) {
        #if DEBUG
        logger.debug("dashboard bootstrap path=\(path.rawValue, privacy: .public)")
        #endif
    }
}

enum DashboardBootstrapLoaderError: Error, Sendable {
    case flagOff
    case rpcUnavailable
}
