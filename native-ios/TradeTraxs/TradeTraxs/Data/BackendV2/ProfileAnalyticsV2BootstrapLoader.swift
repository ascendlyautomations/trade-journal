import Foundation

nonisolated enum ProfileAnalyticsV2BootstrapLoader {
    struct LoadResult: Sendable {
        var applied: ProfileAnalyticsV2BootstrapApplier.Applied
        var encodedByteCount: Int
    }

    static func load(
        viewerScopeID: String,
        profileID: ProfileID,
        rpc: any RPCClient
    ) async throws -> LoadResult {
        let flightKey = BackendV2FlightKeys.profileAnalyticsV2Bootstrap(
            viewerID: viewerScopeID,
            profileID: profileID.rawValue
        )
        let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
            let repo = ProfileAnalyticsV2BootstrapRepository(rpc: rpc)
            let value = try await repo.load(profileID: profileID)
            return try JSONEncoder().encode(value)
        }
        let bootstrap = try JSONDecoder().decode(ProfileAnalyticsBootstrapV2.self, from: data)
        return LoadResult(
            applied: ProfileAnalyticsV2BootstrapApplier.apply(bootstrap),
            encodedByteCount: data.count
        )
    }
}

nonisolated enum ProfilePublicAnalyticsRevisionLoader {
    struct LoadResult: Sendable {
        var payload: ProfilePublicAnalyticsRevisionV1
        var encodedByteCount: Int
    }

    static func load(
        viewerScopeID: String,
        profileID: ProfileID,
        rpc: any RPCClient
    ) async throws -> LoadResult {
        let flightKey = BackendV2FlightKeys.profilePublicAnalyticsRevision(
            viewerID: viewerScopeID,
            profileID: profileID.rawValue
        )
        let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
            let repo = ProfilePublicAnalyticsRevisionRepository(rpc: rpc)
            let value = try await repo.load(profileID: profileID)
            return try JSONEncoder().encode(value)
        }
        let payload = try JSONDecoder().decode(ProfilePublicAnalyticsRevisionV1.self, from: data)
        return LoadResult(payload: payload, encodedByteCount: data.count)
    }
}
