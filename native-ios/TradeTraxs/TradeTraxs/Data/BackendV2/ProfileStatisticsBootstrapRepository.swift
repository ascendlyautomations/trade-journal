import Foundation

nonisolated struct ProfileStatisticsRpcRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(profileID: ProfileID) async throws -> ProfileStatisticsBootstrapV1 {
        let args = ProfileStatisticsRpcArguments(p_profile_id: profileID.rawValue)
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .profileStatisticsBootstrap,
            argumentsJSON: body,
            as: ProfileStatisticsBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.profile.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct ProfileStatisticsRpcArguments: Encodable, Sendable {
    var p_profile_id: String
}

enum ProfileStatisticsBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    @MainActor
    static func load(
        profileID: ProfileID,
        rpc: any RPCClient
    ) async throws -> ProfileStatisticsBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.profile) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.profileStatisticsBootstrap.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(
            rpcName: rpcName,
            viewerID: profileID.rawValue
        ) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.profileStatistics(profileID: profileID.rawValue)
        let bootstrap: ProfileStatisticsBootstrapV1
        do {
            let data = try await BootstrapTransportTimeout.run {
                try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                    let repo = ProfileStatisticsRpcRepository(rpc: rpc)
                    let value = try await repo.load(profileID: profileID)
                    return try JSONEncoder().encode(value)
                }
            }
            bootstrap = try JSONDecoder().decode(ProfileStatisticsBootstrapV1.self, from: data)
        } catch {
            #if DEBUG
            ProfileStatisticsBootstrapFailureDiagnostic.log(rpcName: rpcName, error: error)
            #endif
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: profileID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        return ProfileStatisticsBootstrapApplier.apply(bootstrap)
    }
}
