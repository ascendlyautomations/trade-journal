import Foundation

enum ProfileTabKind: String, Sendable {
    case trades
    case posts
    case reels
    case achievements

    var rpcName: BackendV2Versioning.RPCName {
        switch self {
        case .trades: return .profileTabTrades
        case .posts: return .profileTabPosts
        case .reels: return .profileTabReels
        case .achievements: return .profileTabAchievements
        }
    }
}

nonisolated struct ProfileTabRpcRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(
        tab: ProfileTabKind,
        profileID: ProfileID,
        limit: Int,
        cursor: String?
    ) async throws -> ProfileTabBootstrapV1 {
        let args = ProfileTabRpcArguments(
            p_profile_id: profileID.rawValue,
            p_limit: limit,
            p_cursor: cursor
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            tab.rpcName,
            argumentsJSON: body,
            as: ProfileTabBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.profile.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct ProfileTabRpcArguments: Encodable, Sendable {
    var p_profile_id: String
    var p_limit: Int
    var p_cursor: String?

    enum CodingKeys: String, CodingKey {
        case p_profile_id
        case p_limit
        case p_cursor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_profile_id, forKey: .p_profile_id)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
    }
}

enum ProfileTabBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    static let defaultPageSize = 24

    @MainActor
    static func load(
        tab: ProfileTabKind,
        profileID: ProfileID,
        rpc: any RPCClient,
        cursor: String?,
        limit: Int = defaultPageSize
    ) async throws -> ProfileTabBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.profile) else {
            throw LoaderError.flagOff
        }

        let rpcName = tab.rpcName.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(
            rpcName: rpcName,
            viewerID: profileID.rawValue
        ) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.profileTab(
            tab: tab.rawValue,
            profileID: profileID.rawValue,
            cursor: cursor,
            limit: limit
        )

        let bootstrap: ProfileTabBootstrapV1
        do {
            let data = try await BootstrapTransportTimeout.run {
                try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                    let repo = ProfileTabRpcRepository(rpc: rpc)
                    let value = try await repo.load(
                        tab: tab,
                        profileID: profileID,
                        limit: limit,
                        cursor: cursor
                    )
                    return try JSONEncoder().encode(value)
                }
            }
            bootstrap = try JSONDecoder().decode(ProfileTabBootstrapV1.self, from: data)
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

        return ProfileTabBootstrapApplier.apply(bootstrap, tab: tab, ownerID: profileID)
    }
}
