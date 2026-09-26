import Foundation

nonisolated struct AnalyticsDashboardBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc, enforceKnownNames: false)
    }

    func load() async throws -> AnalyticsDashboardBootstrapV3 {
        let value = try await client.call(
            BackendV2Versioning.RPCName.analyticsDashboardBootstrapV3.rawValue,
            argumentsJSON: Data("{}".utf8),
            as: AnalyticsDashboardBootstrapV3.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.dashboardAnalyticsV3.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

enum DashboardAnalyticsV3Loader {
    struct LoadResult: Sendable {
        var bootstrap: AnalyticsDashboardBootstrapV3
        var source: String
        var payloadBytes: Int?
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        forceNetwork: Bool
    ) async throws -> LoadResult {
        guard SessionViewerGate.shared.allowsDisplay(owner: viewerID.rawValue) else {
            throw CancellationError()
        }
        if !forceNetwork, let cached = DashboardAnalyticsDiskCache.load(viewerID: viewerID) {
            return LoadResult(bootstrap: cached.payload, source: "disk", payloadBytes: nil)
        }

        let started = CFAbsoluteTimeGetCurrent()
        let bootstrap = try await DashboardAnalyticsV3AuthoritativeFetch.fetchNetwork(
            viewerID: viewerID,
            rpc: rpc,
            reason: forceNetwork ? "dashboardLoad.authoritative" : "dashboardLoad.miss"
        )
        guard SessionViewerGate.shared.allowsDisplay(owner: viewerID.rawValue) else {
            throw CancellationError()
        }
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        let encoded = try? JSONEncoder().encode(bootstrap)
        let bytes = encoded?.count
        #if DEBUG
        let breakdown = DashboardAnalyticsV3PayloadProbe.measure(bootstrap)
        DashboardAnalyticsV3PayloadProbe.log(breakdown)
        #endif

        DashboardAnalyticsV3Probe.log(
            source: "network",
            reason: forceNetwork ? "authoritative" : "miss",
            range: nil,
            account: nil,
            mode: nil,
            revision: bootstrap.data.revisionInt,
            payloadBytes: bytes,
            summaryCount: bootstrap.data.aggregatePresets.count,
            dailyRows: 0,
            equityPoints: nil,
            elapsedMs: elapsedMs
        )

        DashboardAnalyticsDiskCache.save(
            DashboardAnalyticsDiskCache.Blob(
                viewerID: viewerID.rawValue,
                contractVersion: BackendV2Versioning.contractVersion,
                schemaVersion: DashboardAnalyticsDiskCache.schemaVersion,
                revision: bootstrap.data.revisionInt,
                savedAt: Date(),
                payload: bootstrap
            )
        )

        AnalyticsDashboardShadowWriter.ingestBootstrapIfNeeded(
            viewerID: viewerID,
            bootstrap: bootstrap
        )

        return LoadResult(bootstrap: bootstrap, source: "network", payloadBytes: bytes)
    }
}
