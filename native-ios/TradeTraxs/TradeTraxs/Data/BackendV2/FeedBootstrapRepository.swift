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
        /// Filter reload cache-only pass — no session snapshot for this filter yet.
        case cacheMissSkipped
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
        forceNetwork: Bool,
        allowNetwork: Bool = true,
        guestPublicMode: Bool = false,
        traceTrigger: String = "feed.initial"
    ) async throws -> (
        entries: [FeedTimelineEntry],
        nextCursor: String?,
        stories: [Story],
        engagement: [InteractionTarget: EngagementSnapshot],
        pendingHydrationItems: [FeedItem],
        feedItemOrder: [String]
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
            #if DEBUG
            FeedFilterCacheProbe.logHydrate(
                filter: contentFilter,
                scope: scope,
                source: .exactFilterCache,
                cachedCount: cached.entries.count,
                knownEmpty: cached.entries.isEmpty
            )
            #endif
            if !guestPublicMode {
                await FollowMutationCoordinator.shared.hydrateViewerFollowingRelationshipsIfNeeded(viewer: viewerID)
            }
            let cachedEntries = guestPublicMode
                ? cached.entries
                : FeedViewerOwnershipFilter.filterEntries(cached.entries, viewerID: viewerID)
            let engagement = guestPublicMode
                ? [:]
                : FeedEngagementCacheRestore.engagementMap(from: cachedEntries)
            return (cachedEntries, cached.nextCursor, cached.stories, engagement, [], [])
        }

        #if DEBUG
        if cursor == nil {
            let resolved = FeedSessionStore.shared.resolvedEntries(
                viewerID: viewerID,
                scope: scope,
                contentFilter: contentFilter
            )
            FeedFilterCacheProbe.logHydrate(
                filter: contentFilter,
                scope: scope,
                source: resolved.entries.isEmpty ? .none : resolved.source,
                cachedCount: resolved.entries.count,
                knownEmpty: resolved.entries.isEmpty
            )
        }
        #endif

        guard allowNetwork else {
            throw LoaderError.cacheMissSkipped
        }

        let rpcName = BackendV2Versioning.RPCName.feed.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.feed(
            viewerID: viewerID.rawValue,
            scope: scope.rawValue,
            contentFilter: contentFilter.rpcValue,
            cursor: cursor
        )

        let bootstrap: FeedBootstrapV1
        do {
            let intentID = BootstrapRpcTrace.beginIntent(
                rpc: rpcName,
                trigger: traceTrigger,
                forceNetwork: forceNetwork
            )
            let joinedExisting = await BackendV2SingleFlight.shared.hasInFlight(key: flightKey)
            let waiterCount = await BackendV2SingleFlight.shared.inFlightWaiterCount(key: flightKey)
            BootstrapRpcTrace.recordSingleFlightJoin(
                intentID: intentID,
                rpc: rpcName,
                joinedExisting: joinedExisting,
                waiterCount: waiterCount + (joinedExisting ? 1 : 0)
            )
            let httpRequestID = UUID()
            let httpStarted = CFAbsoluteTimeGetCurrent()
            BootstrapRpcTrace.httpWillStart(intentID: intentID, requestID: httpRequestID, rpc: rpcName)
            let data = try await BootstrapTransportTimeout.run {
                try await BootstrapRpcTrace.runWithIntent(
                    intentID: intentID,
                    trigger: traceTrigger,
                    rpc: rpcName
                ) {
                    try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                        let repo = FeedRpcBootstrapRepository(rpc: rpc)
                        let rpcScope = guestPublicMode ? FeedScope.global.rawValue : scope.rawValue
                        let value = try await repo.loadFeedBootstrap(
                            scope: rpcScope,
                            contentFilter: contentFilter.rpcValue,
                            cursor: cursor,
                            limit: limit
                        )
                        return try JSONEncoder().encode(value)
                    }
                }
            }
            BootstrapRpcTrace.httpCompleted(
                intentID: intentID,
                requestID: httpRequestID,
                rpc: rpcName,
                elapsedMs: (CFAbsoluteTimeGetCurrent() - httpStarted) * 1000
            )
            bootstrap = try JSONDecoder().decode(FeedBootstrapV1.self, from: data)
            #if DEBUG
            if guestPublicMode {
                ExploreGuestFeedDiagnostics.logSuccess(rpc: rpcName)
            }
            #endif
        } catch {
            #if DEBUG
            if guestPublicMode {
                ExploreGuestFeedDiagnostics.logFailure(rpc: rpcName, error: error)
            }
            #endif
            if cursor == nil,
               let cached = FeedSessionStore.shared.restore(key: cacheKey)
            {
                if !guestPublicMode {
                    await FollowMutationCoordinator.shared.hydrateViewerFollowingRelationshipsIfNeeded(viewer: viewerID)
                }
                let cachedEntries = guestPublicMode
                    ? cached.entries
                    : FeedViewerOwnershipFilter.filterEntries(cached.entries, viewerID: viewerID)
                let engagement = guestPublicMode
                    ? [:]
                    : FeedEngagementCacheRestore.engagementMap(from: cachedEntries)
                return (cachedEntries, cached.nextCursor, cached.stories, engagement, [], [])
            }
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue)
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        let applied = FeedBootstrapApplier.apply(bootstrap)
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: detailCache)
        let followingIDs = Set(
            bootstrap.data.following_ids_echo
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { ProfileID($0) }
        )
        if !guestPublicMode {
            FollowMutationCoordinator.shared.seedViewerFollowingRelationships(
                ids: followingIDs,
                viewer: viewerID
            )
        }
        #if DEBUG
        FeedProgressiveRenderProbe.recordBootstrapDecoded(count: applied.items.count)
        #endif

        let feedItemOrder = applied.items.filter { $0.kind != .story }.map(\.id)
        var entries = FeedSupport.sortDescending(
            FeedBootstrap.buildEntriesFromSeededItems(applied.items, detailCache: detailCache)
        )
        if !guestPublicMode {
            entries = FeedViewerOwnershipFilter.filterEntries(entries, viewerID: viewerID)
        }

        #if DEBUG
        FeedProgressiveRenderProbe.recordRowsPublished(count: entries.count)
        #endif

        let builtIDs = Set(entries.map(\.id))
        let pendingHydrationItems = applied.items.filter {
            $0.kind != .story && !builtIDs.contains($0.id)
        }

        if cursor == nil {
            let snapshot = FeedSessionStore.Snapshot(
                cacheKey: cacheKey,
                entries: entries,
                stories: applied.stories,
                nextCursor: applied.nextCursor,
                loadedAt: Date()
            )
            FeedSessionStore.shared.save(snapshot)
            FeedPersistedCacheCoordinator.persist(snapshot: snapshot)
            #if DEBUG
            FeedPersistentCacheProbe.recordNetworkBootstrap(items: entries.count)
            #endif
        }

        let engagement = guestPublicMode ? [:] : applied.engagementByTarget

        return (
            entries,
            applied.nextCursor,
            applied.stories,
            engagement,
            pendingHydrationItems,
            feedItemOrder
        )
    }
}
