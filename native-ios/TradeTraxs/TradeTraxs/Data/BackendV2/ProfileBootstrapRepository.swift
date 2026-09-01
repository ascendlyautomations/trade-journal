import Foundation

nonisolated struct ProfileRpcBootstrapRepository: ProfileBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadProfileBootstrap(
        profileID: String?,
        username: String?
    ) async throws -> ProfileBootstrapV1 {
        let identifier = profileID ?? username ?? ""
        let args = ProfileRpcArguments(
            p_identifier: identifier,
            p_initial_tab: "trades",
            p_limit: 6,
            p_cursor: nil
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .profile,
            argumentsJSON: body,
            as: ProfileBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.profile.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct ProfileRpcArguments: Encodable, Sendable {
    var p_identifier: String
    var p_initial_tab: String
    var p_limit: Int
    var p_cursor: String?

    enum CodingKeys: String, CodingKey {
        case p_identifier
        case p_initial_tab
        case p_limit
        case p_cursor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_identifier, forKey: .p_identifier)
        try container.encode(p_initial_tab, forKey: .p_initial_tab)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
    }
}

enum ProfileBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
        case profileNotFound
    }

    @MainActor
    static func load(
        profileID: ProfileID,
        username: String?,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        forceNetwork: Bool
    ) async throws -> ProfileState {
        guard BackendV2FeatureFlags.isEnabled(.profile) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.profile.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: profileID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.profile(profileID: profileID.rawValue)
        let bootstrap: ProfileBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = ProfileRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.loadProfileBootstrap(
                    profileID: profileID.rawValue,
                    username: username
                )
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(ProfileBootstrapV1.self, from: data)
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

        guard bootstrap.meta.found != false, bootstrap.data.profile != nil else {
            throw LoaderError.profileNotFound
        }

        return try ProfileBootstrapApplier.apply(
            bootstrap,
            profileID: profileID,
            detailCache: detailCache,
            engagementStore: engagementStore
        )
    }
}
