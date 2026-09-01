import Foundation

nonisolated struct ActivityRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(limit: Int, cursor: String?) async throws -> ActivityBootstrapV1 {
        let args = ActivityRpcArguments(p_limit: limit, p_cursor: cursor)
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .activity,
            argumentsJSON: body,
            as: ActivityBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.activity.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct ActivityRpcArguments: Encodable, Sendable {
    var p_limit: Int
    var p_cursor: String?

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
    }
}

enum ActivityBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache?,
        limit: Int,
        cursor: String?
    ) async throws -> ActivityBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.activity) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.activity.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.activity(viewerID: viewerID.rawValue, cursor: cursor)
        let bootstrap: ActivityBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = ActivityRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.load(limit: limit, cursor: cursor)
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(ActivityBootstrapV1.self, from: data)
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

        return ActivityBootstrapApplier.apply(bootstrap, detailCache: detailCache)
    }
}
