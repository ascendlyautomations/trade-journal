import Foundation

enum ProfileAnalyticsPresentationCoordinator {
    enum Source: String, Sendable {
        case grdb
        case networkV2
    }

    struct Request: Sendable {
        var subjectProfileID: ProfileID
        var visibility: ProfileAnalyticsVisibilityIdentity
        var canViewStatistics: Bool
        var forceNetwork: Bool
        var loadGeneration: UInt64
    }

    struct Response: Sendable {
        var modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
        var source: Source
        var publicRevision: Int64?
    }

    static var usesProfileAnalyticsV2: Bool {
        BackendV2FeatureFlags.isEnabled(.profileAnalyticsV2)
    }

    static var usesProfileAnalyticsGRDB: Bool {
        usesProfileAnalyticsV2 && BackendV2FeatureFlags.isEnabled(.profileAnalyticsGRDB)
    }

    static func load(
        request: Request,
        session: any SessionProviding,
        rpc: any RPCClient
    ) async throws -> Response? {
        guard usesProfileAnalyticsV2 else { return nil }

        let viewerScope = await ProfileAnalyticsV2ShadowCoordinator.viewerScopeID(session: session)
        let store = AnalyticsLocalStore()
        let cacheKey = store.profileAnalyticsCacheKey(
            viewerScopeID: viewerScope,
            subjectProfileID: request.subjectProfileID,
            visibility: request.visibility
        )

        if !request.canViewStatistics {
            try? await store.deleteProfileAnalyticsSnapshots(
                viewerID: cacheKey.viewerID,
                subjectProfileID: cacheKey.subjectProfileID
            )
            return nil
        }

        try? await store.deleteIncompatibleProfileAnalyticsSnapshots(
            viewerID: cacheKey.viewerID,
            subjectProfileID: cacheKey.subjectProfileID,
            expectedVisibility: cacheKey.visibilityIdentity
        )

        if request.forceNetwork {
            return try await fetchNetworkV2(
                request: request,
                rpc: rpc,
                viewerScope: viewerScope,
                cacheKey: cacheKey,
                store: store
            )
        }

        if usesProfileAnalyticsGRDB {
            if let cached = try await store.readProfileAnalyticsSnapshot(key: cacheKey),
               !cached.modeResults.isEmpty {
                ProfileAnalyticsGRDBProbe.logRender(
                    viewer: cacheKey.viewerID,
                    subject: cacheKey.subjectProfileID,
                    revision: cached.publicRevision,
                    source: Source.grdb.rawValue
                )
                if let reconciled = try await reconcileRevision(
                    request: request,
                    rpc: rpc,
                    viewerScope: viewerScope,
                    cacheKey: cacheKey,
                    cachedRevision: cached.publicRevision,
                    cachedModes: cached.modeResults,
                    store: store
                ) {
                    return reconciled
                }
            }
        }

        return try await fetchNetworkV2(
            request: request,
            rpc: rpc,
            viewerScope: viewerScope,
            cacheKey: cacheKey,
            store: store
        )
    }

    static func handleLockedProfile(
        subjectProfileID: ProfileID,
        session: any SessionProviding
    ) async {
        guard usesProfileAnalyticsGRDB else { return }
        let viewerScope = await ProfileAnalyticsV2ShadowCoordinator.viewerScopeID(session: session)
        let store = AnalyticsLocalStore()
        let viewer = viewerScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let subject = subjectProfileID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try? await store.deleteProfileAnalyticsSnapshots(viewerID: viewer, subjectProfileID: subject)
    }

    private static func reconcileRevision(
        request: Request,
        rpc: any RPCClient,
        viewerScope: String,
        cacheKey: AnalyticsLocalStore.ProfileAnalyticsCacheKey,
        cachedRevision: Int64,
        cachedModes: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result],
        store: AnalyticsLocalStore
    ) async throws -> Response? {
        do {
            let revisionLoad = try await ProfilePublicAnalyticsRevisionLoader.load(
                viewerScopeID: viewerScope,
                profileID: request.subjectProfileID,
                rpc: rpc
            )
            guard await isStillValid(request: request) else { return nil }

            if !revisionLoad.payload.meta.found {
                try? await store.deleteProfileAnalyticsSnapshots(
                    viewerID: cacheKey.viewerID,
                    subjectProfileID: cacheKey.subjectProfileID
                )
                return nil
            }

            let serverRevision = revisionLoad.payload.revisionInt ?? cachedRevision
            if serverRevision == cachedRevision {
                ProfileAnalyticsGRDBProbe.logRevisionCurrent(
                    viewer: cacheKey.viewerID,
                    subject: cacheKey.subjectProfileID,
                    revision: cachedRevision
                )
                return Response(
                    modeResults: cachedModes,
                    source: .grdb,
                    publicRevision: cachedRevision
                )
            }
            if serverRevision > cachedRevision {
                ProfileAnalyticsGRDBProbe.logRevisionStale(
                    viewer: cacheKey.viewerID,
                    subject: cacheKey.subjectProfileID,
                    cached: cachedRevision,
                    server: serverRevision
                )
                return try await fetchNetworkV2(
                    request: request,
                    rpc: rpc,
                    viewerScope: viewerScope,
                    cacheKey: cacheKey,
                    store: store
                )
            }
            return Response(
                modeResults: cachedModes,
                source: .grdb,
                publicRevision: cachedRevision
            )
        } catch {
            ProfileAnalyticsGRDBProbe.logFallback(
                viewer: cacheKey.viewerID,
                subject: cacheKey.subjectProfileID,
                reason: "revision_offline"
            )
            if !cachedModes.isEmpty {
                return Response(
                    modeResults: cachedModes,
                    source: .grdb,
                    publicRevision: cachedRevision
                )
            }
            return nil
        }
    }

    private static func fetchNetworkV2(
        request: Request,
        rpc: any RPCClient,
        viewerScope: String,
        cacheKey: AnalyticsLocalStore.ProfileAnalyticsCacheKey,
        store: AnalyticsLocalStore
    ) async throws -> Response? {
        let bootstrapLoad = try await ProfileAnalyticsV2BootstrapLoader.load(
            viewerScopeID: viewerScope,
            profileID: request.subjectProfileID,
            rpc: rpc
        )
        guard await isStillValid(request: request) else { return nil }

        guard bootstrapLoad.applied.found else {
            try? await store.deleteProfileAnalyticsSnapshots(
                viewerID: cacheKey.viewerID,
                subjectProfileID: cacheKey.subjectProfileID
            )
            return nil
        }

        let revision = bootstrapLoad.applied.publicRevision ?? 0
        if usesProfileAnalyticsGRDB {
            try await store.ingestProfileAnalyticsSnapshot(
                key: cacheKey,
                publicRevision: revision,
                modeResults: bootstrapLoad.applied.modeResults
            )
        }

        ProfileAnalyticsGRDBProbe.logRender(
            viewer: cacheKey.viewerID,
            subject: cacheKey.subjectProfileID,
            revision: revision,
            source: Source.networkV2.rawValue
        )

        return Response(
            modeResults: bootstrapLoad.applied.modeResults,
            source: .networkV2,
            publicRevision: revision
        )
    }

    private static func isStillValid(request: Request) async -> Bool {
        let generation = await ProfileAnalyticsGRDBSession.shared.currentGeneration()
        guard generation == request.loadGeneration else { return false }
        guard await ProfileAnalyticsGRDBSession.shared.isActiveSubjectProfile(
            request.subjectProfileID.rawValue
        ) else { return false }
        return true
    }
}
