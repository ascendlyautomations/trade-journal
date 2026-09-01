import Foundation

nonisolated struct ExploreRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(traderOffset: Int) async throws -> ExploreBootstrapV1 {
        let args = ExploreRpcArguments(
            p_trader_limit: 24,
            p_room_limit: 12,
            p_trader_offset: traderOffset
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .explore,
            argumentsJSON: body,
            as: ExploreBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.explore.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct ExploreRpcArguments: Encodable, Sendable {
    var p_trader_limit: Int
    var p_room_limit: Int
    var p_trader_offset: Int
}

enum ExploreBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        traderOffset: Int = 0
    ) async throws -> ExploreBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.explore) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.explore.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.explore(
            viewerID: viewerID.rawValue,
            traderOffset: traderOffset
        )
        let bootstrap: ExploreBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = ExploreRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.load(traderOffset: traderOffset)
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(ExploreBootstrapV1.self, from: data)
            try bootstrap.validateContractVersion()
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: viewerID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        return ExploreBootstrapApplier.apply(
            bootstrap,
            viewerID: viewerID,
            detailCache: detailCache
        )
    }
}
