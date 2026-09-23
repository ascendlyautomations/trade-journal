import Foundation

/// Session-scoped Feed/Profile entity Realtime — bounded author + tracked-entity routes.
@MainActor
final class SocialEntityRealtimeSession {
    static let shared = SocialEntityRealtimeSession()

    struct FeedBinding {
        var viewerID: ProfileID
        var scope: FeedScope
        var followingAuthorIDs: Set<String>?
        var trackedEntityIDsByTable: [SocialEntityRealtimeTable: Set<String>]
    }

    struct ProfileBinding {
        var viewerID: ProfileID
        var profileID: ProfileID
    }

    private var realtimeHub: RealtimeHub?
    private var session: (any SessionProviding)?
    private var feedBinding: FeedBinding?
    private var profileBinding: ProfileBinding?
    private var boundGeneration: UInt64 = 0

    private struct ActiveRoute {
        var consumer: RealtimeRouteConsumerHandle
        var task: Task<Void, Never>
    }

    private var activeRoutes: [String: ActiveRoute] = [:]
    private var reconcileToken: UInt64 = 0

    private init() {}

    func configure(realtimeHub: RealtimeHub?, session: any SessionProviding) {
        self.realtimeHub = realtimeHub
        self.session = session
    }

    func updateFeedBinding(_ binding: FeedBinding?) {
        feedBinding = binding
        enqueueReconcile()
    }

    func updateProfileBinding(_ binding: ProfileBinding?) {
        profileBinding = binding
        enqueueReconcile()
    }

    private func enqueueReconcile() {
        reconcileToken &+= 1
        let token = reconcileToken
        Task { await reconcileRoutes(expectedToken: token) }
    }

    func invalidate() {
        #if DEBUG
        SocialEntityRealtimeDebugLog.sessionClear(reason: "logout")
        #endif
        feedBinding = nil
        profileBinding = nil
        boundGeneration &+= 1
        Task { await tearDownAllRoutes() }
        SocialEntityRealtimeProcessor.shared.resetSession()
    }

    /// Reconcile following-scoped author routes when the complete following set changes (Phase 10E).
    func syncFollowingAuthorsFromSession(viewerID: ProfileID) async {
        guard var feed = feedBinding, feed.viewerID == viewerID, feed.scope == .following else { return }
        guard await SessionFollowingStore.shared.isComplete(viewerID: viewerID.rawValue),
              let cached = await SessionFollowingStore.shared.cached(viewerID: viewerID.rawValue)
        else { return }
        feed.followingAuthorIDs = cached
        feedBinding = feed
        reconcileToken &+= 1
        let token = reconcileToken
        await reconcileRoutes(expectedToken: token)
    }

    // MARK: - Routes

    private func reconcileRoutes(expectedToken: UInt64? = nil) async {
        if let expectedToken, expectedToken != reconcileToken { return }
        guard let realtimeHub, let session else { return }
        guard let viewerID = await session.currentUserID?.rawValue else {
            await tearDownAllRoutes()
            return
        }
        let generation = boundGeneration

        var desired: [String: (SocialEntityRealtimeTable, String)] = [:]

        if let feed = feedBinding, feed.viewerID.rawValue == viewerID {
            if feed.scope == .following, let authors = feed.followingAuthorIDs, !authors.isEmpty {
                var authorList = Array(authors)
                if !authorList.contains(viewerID) {
                    authorList.append(viewerID)
                }
                for table in SocialEntityRealtimeTable.allCases {
                    let chunks = chunk(authorList, size: SocialEntityRealtimeTable.inFilterMaxIDs)
                    for chunk in chunks {
                        let filter = SocialEntityRealtimeTable.realtimeAuthorFilter(
                            table: table,
                            authorIDs: chunk
                        )
                        let suffix = SocialEntityRealtimeTable.stableRouteSuffix(
                            table: table,
                            key: "authors-\(chunk.joined(separator: ","))"
                        )
                        let routeKey = "social-entity:\(suffix)"
                        desired[routeKey] = (table, filter)
                    }
                }
            }
            for (table, ids) in feed.trackedEntityIDsByTable where !ids.isEmpty {
                let chunks = chunk(Array(ids).sorted(), size: SocialEntityRealtimeTable.inFilterMaxIDs)
                for chunk in chunks {
                    let filter = SocialEntityRealtimeTable.realtimeEntityFilter(table: table, entityIDs: chunk)
                    let suffix = SocialEntityRealtimeTable.stableRouteSuffix(
                        table: table,
                        key: "ids-\(chunk.joined(separator: ","))"
                    )
                    let routeKey = "social-entity:\(suffix)"
                    desired[routeKey] = (table, filter)
                }
            }
        }

        if let profile = profileBinding,
           profile.viewerID.rawValue == viewerID
        {
            let owner = profile.profileID.rawValue
            for table in SocialEntityRealtimeTable.allCases {
                let filter = "\(table.authorColumn)=eq.\(owner)"
                let suffix = SocialEntityRealtimeTable.stableRouteSuffix(
                    table: table,
                    key: "profile-\(owner)"
                )
                let routeKey = "social-entity:\(suffix)"
                desired[routeKey] = (table, filter)
            }
        }

        let stale = Set(activeRoutes.keys).subtracting(desired.keys)
        for key in stale {
            await releaseRoute(key)
        }

        for (routeKey, spec) in desired {
            if let expectedToken, expectedToken != reconcileToken { return }
            if activeRoutes[routeKey] != nil { continue }
            await startRoute(
                routeKey: routeKey,
                table: spec.0,
                filter: spec.1,
                viewerID: viewerID,
                generation: generation,
                realtimeHub: realtimeHub,
                session: session
            )
        }
    }

    private func startRoute(
        routeKey: String,
        table: SocialEntityRealtimeTable,
        filter: String,
        viewerID: String,
        generation: UInt64,
        realtimeHub: RealtimeHub,
        session: any SessionProviding
    ) async {
        let token = await session.accessToken
        let watch = realtimeHub.watchSocialEntityChanges(
            table: table,
            filter: filter,
            accessToken: token,
            debugOwner: "SocialEntityRealtime"
        )
        #if DEBUG
        SocialEntityRealtimeDebugLog.routeJoin(table: table.rawValue, routeKey: routeKey)
        #endif
        let task = Task { [weak self] in
            for await event in watch.events {
                guard !Task.isCancelled else { break }
                guard generation == self?.boundGeneration else { return }
                guard await session.currentUserID?.rawValue == viewerID else { return }
                await SocialEntityRealtimeProcessor.shared.handle(event, viewerUserID: viewerID)
            }
        }
        activeRoutes[routeKey] = ActiveRoute(consumer: watch.consumer, task: task)
    }

    private func chunk(_ values: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: values.count, by: size).map {
            Array(values[$0 ..< min($0 + size, values.count)])
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
        SocialEntityRealtimeDebugLog.routeLeave(routeKey: routeKey)
        #endif
        await realtimeHub?.releaseWatch(route.consumer)
    }
}

#if DEBUG
extension SocialEntityRealtimeSession {
    func testing_activeRouteCount() -> Int { activeRoutes.count }
}
#endif
