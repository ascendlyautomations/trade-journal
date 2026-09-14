import Foundation

/// Leaderboard V2 bootstrap — `rpc_v1_leaderboard_bootstrap`.
nonisolated struct LeaderboardRpcBootstrapRepository: LeaderboardBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadLeaderboardBootstrap(
        timeframe: String,
        category: String,
        audience: String,
        limit: Int,
        cursor: String?
    ) async throws -> LeaderboardBootstrapV1 {
        let args = LeaderboardRpcArguments(
            p_timeframe: timeframe,
            p_category: category,
            p_audience: audience,
            p_limit: limit,
            p_cursor: cursor
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .leaderboard,
            argumentsJSON: body,
            as: LeaderboardBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.leaderboard.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct LeaderboardRpcArguments: Encodable, Sendable {
    var p_timeframe: String
    var p_category: String
    var p_audience: String
    var p_limit: Int
    var p_cursor: String?

    enum CodingKeys: String, CodingKey {
        case p_timeframe
        case p_category
        case p_audience
        case p_limit
        case p_cursor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_timeframe, forKey: .p_timeframe)
        try container.encode(p_category, forKey: .p_category)
        try container.encode(p_audience, forKey: .p_audience)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
    }
}

enum LeaderboardBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    struct Applied: Sendable {
        var entries: [LeaderboardEntry]
        var profiles: [ProfileID: Profile]
        var followers: [ProfileID: Int]
        var nextCursor: String?
        var timeframe: String
        var category: String
    }

    @MainActor
    static func loadPage(
        viewerID: ProfileID?,
        timeframe: LeaderboardTimeframe,
        category: LeaderboardCategory,
        audience: LeaderboardAudience,
        cursor: String?,
        limit: Int,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        forceNetwork: Bool
    ) async throws -> Applied {
        _ = forceNetwork
        guard BackendV2FeatureFlags.isEnabled(.leaderboard) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.leaderboard.rawValue
        if let viewerID,
           await BackendV2RpcAvailability.shared.isUnavailable(
               rpcName: rpcName,
               viewerID: viewerID.rawValue
           )
        {
            throw LoaderError.rpcUnavailable
        }

        var effectiveTimeframe = timeframe
        var lastApplied: Applied?

        for candidate in LeaderboardTimeframeFallback.candidates(starting: timeframe) {
            let flightKey = BackendV2FlightKeys.leaderboard(
                timeframe: candidate.rpcValue,
                category: category.rawValue,
                audience: audience.rawValue,
                cursor: cursor,
                limit: limit
            )
            let bootstrap: LeaderboardBootstrapV1
            do {
                let data = try await BootstrapTransportTimeout.run {
                    try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                        let repo = LeaderboardRpcBootstrapRepository(rpc: rpc)
                        let value = try await repo.loadLeaderboardBootstrap(
                            timeframe: candidate.rpcValue,
                            category: category.rawValue,
                            audience: audience.rawValue,
                            limit: limit,
                            cursor: cursor
                        )
                        return try JSONEncoder().encode(value)
                    }
                }
                bootstrap = try JSONDecoder().decode(LeaderboardBootstrapV1.self, from: data)
            } catch {
                if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                    if let viewerID {
                        await BackendV2RpcAvailability.shared.markUnavailable(
                            rpcName: rpcName,
                            viewerID: viewerID.rawValue
                        )
                    }
                    throw LoaderError.rpcUnavailable
                }
                throw error
            }

            let mapped = LeaderboardBootstrapApplier.apply(
                bootstrap,
                rankOffset: cursor == nil ? 0 : parsedRankOffset(from: cursor)
            )
            for profile in mapped.profiles.values {
                detailCache.seed(profile)
            }
            effectiveTimeframe = candidate
            lastApplied = Applied(
                entries: mapped.entries,
                profiles: mapped.profiles,
                followers: mapped.followers,
                nextCursor: mapped.nextCursor,
                timeframe: candidate.rpcValue,
                category: category.rawValue
            )
            if !mapped.entries.isEmpty || cursor != nil {
                break
            }
        }

        guard var result = lastApplied else {
            return Applied(
                entries: [],
                profiles: [:],
                followers: [:],
                nextCursor: nil,
                timeframe: effectiveTimeframe.rpcValue,
                category: category.rawValue
            )
        }
        result.timeframe = effectiveTimeframe.rpcValue
        return result
    }

    private static func parsedRankOffset(from cursor: String?) -> Int {
        guard let cursor, let sort = cursor.split(separator: "|").first,
              let _ = Double(sort)
        else { return 0 }
        return 0
    }
}

private extension LeaderboardTimeframeFallback {
    static func candidates(starting requested: LeaderboardTimeframe) -> [LeaderboardTimeframe] {
        guard let index = presetOrder.firstIndex(of: requested) else {
            return presetOrder
        }
        return Array(presetOrder[index...])
    }
}
