import Foundation

nonisolated struct ActivityRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(
        limit: Int,
        cursor: String?,
        filter: ActivityNotificationListFilter = .all
    ) async throws -> ActivityBootstrapV1 {
        let args = ActivityRpcArguments(p_limit: limit, p_cursor: cursor, filter: filter)
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
    var p_types: [String]?
    var p_created_after: String?
    var p_created_before: String?
    var p_achievement_posts_only: Bool
    var p_exclude_achievement_posts: Bool

    init(p_limit: Int, p_cursor: String?, filter: ActivityNotificationListFilter) {
        self.p_limit = p_limit
        self.p_cursor = p_cursor
        self.p_types = filter.types
        self.p_created_after = filter.createdAfter.map { ISO8601.string(from: $0) }
        self.p_created_before = filter.createdBefore.map { ISO8601.string(from: $0) }
        self.p_achievement_posts_only = filter.achievementPostsOnly
        self.p_exclude_achievement_posts = filter.excludeAchievementPosts
    }

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor
        case p_types
        case p_created_after
        case p_created_before
        case p_achievement_posts_only
        case p_exclude_achievement_posts
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
        if let p_types, !p_types.isEmpty {
            try container.encode(p_types, forKey: .p_types)
        } else {
            try container.encodeNil(forKey: .p_types)
        }
        if let p_created_after {
            try container.encode(p_created_after, forKey: .p_created_after)
        } else {
            try container.encodeNil(forKey: .p_created_after)
        }
        if let p_created_before {
            try container.encode(p_created_before, forKey: .p_created_before)
        } else {
            try container.encodeNil(forKey: .p_created_before)
        }
        try container.encode(p_achievement_posts_only, forKey: .p_achievement_posts_only)
        try container.encode(p_exclude_achievement_posts, forKey: .p_exclude_achievement_posts)
    }
}

enum ActivityBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    nonisolated static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        limit: Int,
        cursor: String?,
        filter: ActivityNotificationListFilter = .all
    ) async throws -> ActivityBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.activity) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.activity.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.activity(
            viewerID: viewerID.rawValue,
            limit: limit,
            cursor: cursor,
            filterKey: filter.cacheKey
        )
        let data: Data
        do {
            data = try await BootstrapTransportTimeout.run {
                try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                    let repo = ActivityRpcBootstrapRepository(rpc: rpc)
                    let value = try await repo.load(limit: limit, cursor: cursor, filter: filter)
                    return try JSONEncoder().encode(value)
                }
            }
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

        return try await Task.detached(priority: .utility) {
            let bootstrap = try JSONDecoder().decode(ActivityBootstrapV1.self, from: data)
            try bootstrap.validateContractVersion()
            return ActivityBootstrapApplier.transform(bootstrap)
        }.value
    }
}
