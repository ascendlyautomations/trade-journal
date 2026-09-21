import Foundation

nonisolated struct ProfileAnalyticsV2BootstrapRepository: Sendable {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(profileID: ProfileID) async throws -> ProfileAnalyticsBootstrapV2 {
        let args = ProfileAnalyticsRpcArguments(p_profile_id: profileID.rawValue)
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .profileAnalyticsBootstrapV2,
            argumentsJSON: body,
            as: ProfileAnalyticsBootstrapV2.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.profileAnalyticsV2Shadow.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

nonisolated struct ProfilePublicAnalyticsRevisionRepository: Sendable {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(profileID: ProfileID) async throws -> ProfilePublicAnalyticsRevisionV1 {
        let args = ProfileAnalyticsRpcArguments(p_profile_id: profileID.rawValue)
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .profilePublicAnalyticsRevision,
            argumentsJSON: body,
            as: ProfilePublicAnalyticsRevisionV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.profileAnalyticsV2Shadow.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct ProfileAnalyticsRpcArguments: Encodable, Sendable {
    var p_profile_id: String
}
