import Foundation
import os

/// Dashboard V2 bootstrap — `rpc_v1_dashboard_bootstrap`.
nonisolated struct DashboardRpcBootstrapRepository: DashboardBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadDashboardBootstrap(accountID: String?) async throws -> DashboardBootstrapV1 {
        let args = DashboardRpcArguments(p_account_id: accountID, p_trade_limit: 500)
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
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) async throws -> DashboardBootstrapLoadResult {
        guard BackendV2FeatureFlags.isEnabled(.dashboard) else {
            throw DashboardBootstrapLoaderError.flagOff
        }

        let uid = viewerID.rawValue
        let accountScope = "all"

        if !forceNetwork, let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: uid) {
            let applied = try await DashboardBootstrapApplier.apply(
                cached.bootstrap,
                expectedViewerID: uid,
                detailCache: detailCache
            )
            logPath(cached.freshness == .fresh ? .cache_fresh : .cache_stale_revalidate)
            if cached.freshness == .softStale, !forceNetwork {
                Task { @MainActor in
                    await revalidateIfCurrent(
                        viewerID: viewerID,
                        rpc: rpc,
                        detailCache: detailCache,
                        loadGeneration: loadGeneration,
                        currentGeneration: currentGeneration
                    )
                }
            }
            return DashboardBootstrapLoadResult(
                applied: applied,
                path: cached.freshness == .fresh ? .cache_fresh : .cache_stale_revalidate,
                rpcRequestCount: 0
            )
        }

        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: uid) {
            throw DashboardBootstrapLoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.dashboard(viewerID: uid, accountID: nil)
        do {
            let bootstrap = try await fetchRPC(
                viewerID: uid,
                rpc: rpc,
                flightKey: flightKey
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
    private static func revalidateIfCurrent(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) async {
        guard currentGeneration() == loadGeneration else { return }
        do {
            _ = try await load(
                viewerID: viewerID,
                rpc: rpc,
                detailCache: detailCache,
                forceNetwork: true,
                loadGeneration: loadGeneration,
                currentGeneration: currentGeneration
            )
        } catch {
            // Preserve cached presentation — non-fatal.
        }
    }

    private static func fetchRPC(
        viewerID: String,
        rpc: any RPCClient,
        flightKey: String
    ) async throws -> DashboardBootstrapV1 {
        let repo = DashboardRpcBootstrapRepository(rpc: rpc)
        let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
            let bootstrap = try await repo.loadDashboardBootstrap(accountID: nil)
            let encoded = try JSONEncoder().encode(bootstrap)
            return encoded
        }
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
