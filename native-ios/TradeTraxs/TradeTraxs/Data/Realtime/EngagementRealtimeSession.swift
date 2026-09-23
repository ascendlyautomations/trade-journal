import Foundation

/// Session-scoped content-like Realtime — bounded targets only, grouped routes.
@MainActor
final class EngagementRealtimeSession {
    static let shared = EngagementRealtimeSession()

    private var realtimeHub: RealtimeHub?
    private var session: (any SessionProviding)?
    private var database: (any SupabaseDatabaseExecuting)?
    private weak var engagementStore: EngagementStore?

    private var retentionByOwner: [String: Set<InteractionTarget>] = [:]
    private var contentIDByTarget: [InteractionTarget: String] = [:]
    private var boundViewerID: String?
    private var boundGeneration: UInt64 = 0

    private struct ActiveRoute {
        var consumer: RealtimeRouteConsumerHandle
        var task: Task<Void, Never>
        var table: ContentLikeTable
        var contentIDs: Set<String>
    }

    private var activeRoutes: [String: ActiveRoute] = [:]
    private var reconcileToken: UInt64 = 0
    private var seenEventKeys: Set<String> = []
    private let maxSeenEventKeys = 2_048

    private init() {}

    func configure(
        realtimeHub: RealtimeHub?,
        session: any SessionProviding,
        database: any SupabaseDatabaseExecuting,
        engagementStore: EngagementStore
    ) {
        self.realtimeHub = realtimeHub
        self.session = session
        self.database = database
        self.engagementStore = engagementStore
    }

    /// Replace the retained target set for one UI owner (Feed visible, profile tab, detail, …).
    func updateRetention(ownerKey: String, targets: Set<InteractionTarget>) {
        if targets.isEmpty {
            retentionByOwner.removeValue(forKey: ownerKey)
        } else {
            retentionByOwner[ownerKey] = targets
        }
        enqueueReconcile()
    }

    private func enqueueReconcile() {
        reconcileToken &+= 1
        let token = reconcileToken
        Task { await reconcileRoutes(expectedToken: token) }
    }

    func invalidate() {
        #if DEBUG
        EngagementRealtimeDebugLog.sessionClear(reason: "logout")
        #endif
        retentionByOwner.removeAll()
        contentIDByTarget.removeAll()
        boundViewerID = nil
        boundGeneration &+= 1
        seenEventKeys.removeAll()
        Task { await tearDownAllRoutes() }
    }

    // MARK: - Private

    private var unionTargets: Set<InteractionTarget> {
        retentionByOwner.values.reduce(into: Set<InteractionTarget>()) { $0.formUnion($1) }
    }

    private func reconcileRoutes(expectedToken: UInt64? = nil) async {
        if let expectedToken, expectedToken != reconcileToken { return }
        guard let realtimeHub, let session else { return }
        guard let viewerID = await session.currentUserID?.rawValue else {
            await tearDownAllRoutes()
            return
        }
        if boundViewerID != viewerID {
            boundViewerID = viewerID
            boundGeneration &+= 1
            seenEventKeys.removeAll()
        }
        let generation = boundGeneration

        let targets = unionTargets
        #if DEBUG
        let kindSummary = Dictionary(grouping: targets, by: \.kind.rawValue)
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        EngagementRealtimeDebugLog.retainTargets(count: targets.count, kinds: kindSummary)
        #endif

        await resolveContentIDs(for: targets)

        var desiredRoutes: [String: (ContentLikeTable, Set<String>)] = [:]
        let grouped = Dictionary(grouping: targets) { ContentLikeTable.from($0.kind) }
        for (table, tableTargets) in grouped {
            let ids = tableTargets.compactMap { contentIDByTarget[$0] }.filter { !$0.isEmpty }
            let unique = Array(Set(ids)).sorted()
            guard !unique.isEmpty else { continue }
            let chunks = stride(from: 0, to: unique.count, by: ContentLikeSemantics.realtimeInFilterMaxIDs).map {
                Array(unique[$0 ..< min($0 + ContentLikeSemantics.realtimeInFilterMaxIDs, unique.count)])
            }
            for chunk in chunks {
                let suffix = ContentLikeSemantics.stableRouteSuffix(table: table, contentIDs: chunk)
                let routeKey = "content-likes:\(suffix)"
                desiredRoutes[routeKey] = (table, Set(chunk))
            }
        }

        let staleKeys = Set(activeRoutes.keys).subtracting(desiredRoutes.keys)
        for key in staleKeys {
            await releaseRoute(key)
        }

        for (routeKey, spec) in desiredRoutes {
            if let expectedToken, expectedToken != reconcileToken { return }
            if let existing = activeRoutes[routeKey],
               existing.table == spec.0,
               existing.contentIDs == spec.1
            {
                continue
            }
            if activeRoutes[routeKey] != nil {
                await releaseRoute(routeKey)
            }
            await startRoute(
                routeKey: routeKey,
                table: spec.0,
                contentIDs: Array(spec.1).sorted(),
                viewerID: viewerID,
                generation: generation,
                realtimeHub: realtimeHub,
                session: session
            )
        }
    }

    private func resolveContentIDs(for targets: Set<InteractionTarget>) async {
        for target in targets {
            if contentIDByTarget[target] != nil { continue }
            switch target.kind {
            case .achievement:
                if let database,
                   let postID = try? await AchievementInteractionPostIDResolver.shared.postID(
                       for: target.id,
                       database: database
                   )
                {
                    contentIDByTarget[target] = postID
                } else {
                    contentIDByTarget[target] = target.id
                }
            default:
                contentIDByTarget[target] = target.id
            }
        }
        let active = unionTargets
        for key in contentIDByTarget.keys where !active.contains(key) {
            contentIDByTarget.removeValue(forKey: key)
        }
    }

    private func startRoute(
        routeKey: String,
        table: ContentLikeTable,
        contentIDs: [String],
        viewerID: String,
        generation: UInt64,
        realtimeHub: RealtimeHub,
        session: any SessionProviding
    ) async {
        let token = await session.accessToken
        let watch = realtimeHub.watchContentLikes(
            table: table,
            contentIDs: contentIDs,
            accessToken: token,
            debugOwner: "EngagementRealtime"
        )
        #if DEBUG
        EngagementRealtimeDebugLog.routeJoin(
            table: table.rawValue,
            routeKey: routeKey,
            idCount: contentIDs.count
        )
        #endif
        let task = Task { [weak self] in
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                await self?.handleSignal(
                    signal,
                    expectedViewerID: viewerID,
                    generation: generation
                )
            }
        }
        activeRoutes[routeKey] = ActiveRoute(
            consumer: watch.consumer,
            task: task,
            table: table,
            contentIDs: Set(contentIDs)
        )
    }

    private func handleSignal(
        _ signal: ContentLikeRealtimeSignal,
        expectedViewerID: String,
        generation: UInt64
    ) async {
        guard generation == boundGeneration else {
            #if DEBUG
            EngagementRealtimeDebugLog.staleIgnored(reason: "generation")
            #endif
            return
        }
        guard boundViewerID == expectedViewerID else { return }
        guard let session, await session.currentUserID?.rawValue == expectedViewerID else {
            #if DEBUG
            EngagementRealtimeDebugLog.staleIgnored(reason: "viewer_mismatch")
            #endif
            return
        }
        guard let engagementStore else { return }

        if let rowID = signal.rowID, !rowID.isEmpty {
            let dedupeKey = "\(signal.table.rawValue):\(rowID):\(signal.kind)"
            if seenEventKeys.contains(dedupeKey) {
                #if DEBUG
                EngagementRealtimeDebugLog.duplicateIgnored(table: signal.table.rawValue, rowID: rowID)
                #endif
                return
            }
            seenEventKeys.insert(dedupeKey)
            if seenEventKeys.count > maxSeenEventKeys {
                seenEventKeys.removeAll(keepingCapacity: true)
            }
        }

        let targets = unionTargets.filter {
            ContentLikeTable.from($0.kind) == signal.table
                && contentIDByTarget[$0] == signal.contentID
        }
        guard !targets.isEmpty else { return }

        #if DEBUG
        switch signal.kind {
        case .insert:
            EngagementRealtimeDebugLog.eventInsert(
                table: signal.table.rawValue,
                contentID: signal.contentID,
                userID: signal.userID
            )
        case .delete:
            EngagementRealtimeDebugLog.eventDelete(
                table: signal.table.rawValue,
                contentID: signal.contentID,
                userID: signal.userID
            )
        }
        #endif

        for target in targets {
            await engagementStore.applyContentLikeRealtime(
                on: target,
                signal: signal,
                viewerUserID: expectedViewerID
            )
        }
    }

    private func tearDownAllRoutes() async {
        let snapshot = activeRoutes
        activeRoutes = [:]
        for (_, route) in snapshot {
            route.task.cancel()
            await realtimeHub?.releaseWatch(route.consumer)
        }
    }

    private func releaseRoute(_ routeKey: String) async {
        guard let route = activeRoutes.removeValue(forKey: routeKey) else { return }
        route.task.cancel()
        #if DEBUG
        EngagementRealtimeDebugLog.routeLeave(routeKey: routeKey)
        #endif
        await realtimeHub?.releaseWatch(route.consumer)
    }
}

#if DEBUG
extension EngagementRealtimeSession {
    func testing_activeRouteCount() -> Int {
        activeRoutes.count
    }

    func testing_routeKeys() -> [String] {
        activeRoutes.keys.sorted()
    }
}
#endif
