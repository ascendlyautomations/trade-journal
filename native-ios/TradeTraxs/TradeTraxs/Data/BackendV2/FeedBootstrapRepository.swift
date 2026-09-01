import Foundation

/// Feed V2 bootstrap — `rpc_v1_feed_bootstrap`.
nonisolated struct FeedRpcBootstrapRepository: FeedBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadFeedBootstrap(
        scope: String,
        contentFilter: String?,
        cursor: String?,
        limit: Int?
    ) async throws -> FeedBootstrapV1 {
        let args = FeedRpcArguments(
            p_scope: scope,
            p_content_filter: contentFilter ?? "all",
            p_limit: limit ?? 20,
            p_cursor: cursor
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .feed,
            argumentsJSON: body,
            as: FeedBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.feed.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct FeedRpcArguments: Encodable, Sendable {
    var p_scope: String
    var p_content_filter: String
    var p_limit: Int
    var p_cursor: String?

    enum CodingKeys: String, CodingKey {
        case p_scope
        case p_content_filter
        case p_limit
        case p_cursor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_scope, forKey: .p_scope)
        try container.encode(p_content_filter, forKey: .p_content_filter)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
    }
}

enum FeedBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    @MainActor
    static func loadTimeline(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        cursor: String?,
        limit: Int,
        rpc: any RPCClient,
        feed: any FeedRepository,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache,
        forceNetwork: Bool
    ) async throws -> (
        entries: [FeedTimelineEntry],
        nextCursor: String?,
        stories: [Story],
        engagement: [InteractionTarget: EngagementSnapshot]
    ) {
        guard BackendV2FeatureFlags.isEnabled(.feed) else {
            throw LoaderError.flagOff
        }

        let cacheKey = FeedSessionStore.cacheKey(
            viewerID: viewerID,
            scope: scope,
            contentFilter: contentFilter,
            cursor: cursor
        )
        if !forceNetwork, cursor == nil, let cached = FeedSessionStore.shared.restore(key: cacheKey) {
            return (cached.entries, cached.nextCursor, cached.stories, [:])
        }

        let rpcName = BackendV2Versioning.RPCName.feed.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.feed(
            viewerID: viewerID.rawValue,
            scope: scope.rawValue,
            contentFilter: contentFilter.rawValue,
            cursor: cursor
        )

        let bootstrap: FeedBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = FeedRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.loadFeedBootstrap(
                    scope: scope.rawValue,
                    contentFilter: contentFilter.rawValue,
                    cursor: cursor,
                    limit: limit
                )
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(FeedBootstrapV1.self, from: data)
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue)
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        let applied = FeedBootstrapApplier.apply(bootstrap)
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: detailCache)
        var entries = FeedSupport.sortDescending(
            FeedBootstrap.buildEntriesFromSeededItems(applied.items, detailCache: detailCache)
        )

        if entries.count < applied.items.count {
            let builtIDs = Set(entries.map(\.id))
            let missing = applied.items.filter { !builtIDs.contains($0.id) }
            if !missing.isEmpty {
                #if DEBUG
                FeedRpcLoadProbe.recordNetworkHydrate()
                #endif
                let hydrated = await FeedBootstrap.hydrate(
                    missing,
                    feed: feed,
                    trades: trades,
                    profiles: profiles,
                    achievements: achievements,
                    detailCache: detailCache
                )
                entries = FeedSupport.sortDescending(entries + hydrated)
            }
        }

        if cursor == nil {
            FeedSessionStore.shared.save(
                FeedSessionStore.Snapshot(
                    cacheKey: cacheKey,
                    entries: entries,
                    stories: applied.stories,
                    nextCursor: applied.nextCursor,
                    loadedAt: Date()
                )
            )
        }

        return (entries, applied.nextCursor, applied.stories, applied.engagementByTarget)
    }
}
