import Foundation

nonisolated struct PropFirmRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadPropFirmBootstrap() async throws -> PropFirmBootstrapV1 {
        let value = try await client.call(
            .propFirm,
            argumentsJSON: Data("{}".utf8),
            as: PropFirmBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.propFirm.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

enum PropFirmBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
        case accountNotFound
    }

    struct LoadResult: Sendable {
        var snapshot: PropFirmStatusSnapshot
        var seededTradeCount: Int
    }

    @MainActor
    static func load(
        accountID: TradingAccountID,
        profileID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache
    ) async throws -> LoadResult {
        guard BackendV2FeatureFlags.isEnabled(.propFirm) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.propFirm.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: profileID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.propFirm(viewerID: profileID.rawValue)
        let bootstrap: PropFirmBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = PropFirmRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.loadPropFirmBootstrap()
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(PropFirmBootstrapV1.self, from: data)
            try bootstrap.validateContractVersion()
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: profileID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        return try PropFirmBootstrapApplier.apply(
            bootstrap,
            accountID: accountID,
            profileID: profileID,
            detailCache: detailCache
        )
    }
}
