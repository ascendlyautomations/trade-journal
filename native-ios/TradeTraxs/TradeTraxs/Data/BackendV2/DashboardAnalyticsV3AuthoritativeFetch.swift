import Foundation

/// Single-flight authoritative `rpc_v1_analytics_dashboard_bootstrap_v3` network fetch.
nonisolated enum DashboardAnalyticsV3AuthoritativeFetch {
    static func fetchNetwork(
        viewerID: ProfileID,
        rpc: any RPCClient,
        reason: String
    ) async throws -> AnalyticsDashboardBootstrapV3 {
        let flightKey = AnalyticsReconciliationFlightKeys.dashboardV3(viewerID: viewerID.rawValue)
        let joinedExisting = await BackendV2SingleFlight.shared.hasInFlight(key: flightKey)
#if DEBUG
        SupabaseEfficiencyProbe.dashboardV3Request(
            joinedExisting ? .joinedExisting : .new,
            reason: reason
        )
#endif
        let encoded = try await BootstrapTransportTimeout.run {
            try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = AnalyticsDashboardBootstrapRepository(rpc: rpc)
                let bootstrap = try await repo.load()
                return try JSONEncoder().encode(bootstrap)
            }
        }
        let bootstrap = try JSONDecoder().decode(AnalyticsDashboardBootstrapV3.self, from: encoded)
        if let payloadOwner = bootstrap.meta.viewer_id,
           !DashboardSessionIsolation.ownersMatch(payloadOwner, viewerID.rawValue)
        {
            throw BackendV2RPCError.decode("viewer_id mismatch")
        }
        await AnalyticsReconciliationCoordinator.shared.noteAuthoritativeDashboardRevision(
            bootstrap.data.revisionInt,
            viewerID: viewerID
        )
        return bootstrap
    }

    /// Lightweight revision probe — avoids full dashboard bootstrap when local GRDB/VM is current.
    static func fetchRemoteRevision(
        viewerID: ProfileID,
        rpc: any RPCClient
    ) async -> Int64? {
        let flightKey = BackendV2FlightKeys.analyticsRevision(viewerID: viewerID.rawValue)
        do {
            let encoded = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = AnalyticsRevisionRepository(rpc: rpc)
                let response = try await repo.loadRevision()
                return try JSONEncoder().encode(response)
            }
            let server = try JSONDecoder().decode(AnalyticsRevisionV1.self, from: encoded)
            return server.revisionInt
        } catch {
            return nil
        }
    }
}
