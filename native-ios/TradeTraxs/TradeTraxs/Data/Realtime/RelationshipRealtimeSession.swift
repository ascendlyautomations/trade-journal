import Foundation

/// Viewer-scoped relationship Realtime — `followers` + `follow_requests` postgres_changes.
@MainActor
final class RelationshipRealtimeSession {
    static let shared = RelationshipRealtimeSession()

    private var realtimeHub: RealtimeHub?
    private var session: (any SessionProviding)?
    private var boundViewerID: ProfileID?
    private var boundGeneration: UInt64 = 0
    private var watchTask: Task<Void, Never>?
    private var outgoingConsumer: RealtimeRouteConsumerHandle?
    private var incomingConsumer: RealtimeRouteConsumerHandle?
    private var requestsOutConsumer: RealtimeRouteConsumerHandle?
    private var requestsInConsumer: RealtimeRouteConsumerHandle?
    private var seenEventKeys: Set<String> = []
    private let maxSeenEventKeys = 2_048

    private init() {}

    func configure(realtimeHub: RealtimeHub?, session: any SessionProviding) {
        self.realtimeHub = realtimeHub
        self.session = session
    }

    func bindAuthenticatedViewer(_ viewerID: ProfileID) {
        guard boundViewerID != viewerID else { return }
        stopWatch(reason: "viewer_switch")
        boundViewerID = viewerID
        boundGeneration &+= 1
        seenEventKeys.removeAll()
        startWatch(viewerID: viewerID, generation: boundGeneration)
    }

    func invalidate() {
        stopWatch(reason: "logout")
        boundViewerID = nil
        boundGeneration &+= 1
        seenEventKeys.removeAll()
    }

    private func startWatch(viewerID: ProfileID, generation: UInt64) {
        guard let realtimeHub else { return }
        let raw = viewerID.rawValue
        watchTask = Task { [weak self] in
            guard let self else { return }
            let token = await session?.accessToken
            async let outgoing = realtimeHub.watchRelationshipOutgoingFollows(
                userID: raw,
                accessToken: token,
                debugOwner: "RelationshipRealtime.outgoing"
            )
            async let incoming = realtimeHub.watchRelationshipIncomingFollows(
                userID: raw,
                accessToken: token,
                debugOwner: "RelationshipRealtime.incoming"
            )
            async let requestsOut = realtimeHub.watchRelationshipOutgoingFollowRequests(
                userID: raw,
                accessToken: token,
                debugOwner: "RelationshipRealtime.requestsOut"
            )
            async let requestsIn = realtimeHub.watchRelationshipIncomingFollowRequests(
                userID: raw,
                accessToken: token,
                debugOwner: "RelationshipRealtime.requestsIn"
            )
            let watches = await (outgoing, incoming, requestsOut, requestsIn)
            outgoingConsumer = watches.0.consumer
            incomingConsumer = watches.1.consumer
            requestsOutConsumer = watches.2.consumer
            requestsInConsumer = watches.3.consumer

            Task { await self.consumeFollowers(watches.0.events, viewerID: viewerID, generation: generation) }
            Task { await self.consumeFollowers(watches.1.events, viewerID: viewerID, generation: generation) }
            Task {
                await self.consumeFollowRequests(
                    watches.2.events,
                    viewerID: viewerID,
                    generation: generation,
                    asRequester: true
                )
            }
            Task {
                await self.consumeFollowRequests(
                    watches.3.events,
                    viewerID: viewerID,
                    generation: generation,
                    asRequester: false
                )
            }
        }
    }

    private func stopWatch(reason: String) {
        watchTask?.cancel()
        watchTask = nil
        let outgoing = outgoingConsumer
        let incoming = incomingConsumer
        let requestsOut = requestsOutConsumer
        let requestsIn = requestsInConsumer
        outgoingConsumer = nil
        incomingConsumer = nil
        requestsOutConsumer = nil
        requestsInConsumer = nil
        Task { [realtimeHub] in
            await realtimeHub?.releaseWatch(outgoing)
            await realtimeHub?.releaseWatch(incoming)
            await realtimeHub?.releaseWatch(requestsOut)
            await realtimeHub?.releaseWatch(requestsIn)
        }
        _ = reason
    }

    private func consumeFollowers(
        _ events: AsyncStream<MessageRealtimeSignal>,
        viewerID: ProfileID,
        generation: UInt64
    ) async {
        for await signal in events {
            guard !Task.isCancelled else { break }
            guard generation == boundGeneration, boundViewerID == viewerID else { return }
            await handleFollowerSignal(signal, viewerID: viewerID)
        }
    }

    private func consumeFollowRequests(
        _ events: AsyncStream<MessageRealtimeSignal>,
        viewerID: ProfileID,
        generation: UInt64,
        asRequester: Bool
    ) async {
        for await signal in events {
            guard !Task.isCancelled else { break }
            guard generation == boundGeneration, boundViewerID == viewerID else { return }
            await handleFollowRequestSignal(signal, viewerID: viewerID, asRequester: asRequester)
        }
    }

    private func handleFollowerSignal(_ signal: MessageRealtimeSignal, viewerID: ProfileID) async {
        guard let payload = signal.recordPayload,
              let record = PostgresChangeRecordCodec.dictionary(from: payload)
        else { return }

        let followerID = (record["follower_id"] as? String) ?? ""
        let followingID = (record["following_id"] as? String) ?? ""
        guard !followerID.isEmpty, !followingID.isEmpty else { return }

        let eventKey = "followers:\(signal.kind.rawValue):\(followerID):\(followingID)"
        guard claimEvent(eventKey) else { return }

        let viewerRaw = viewerID.rawValue
        switch signal.kind {
        case .insert:
            if followerID == viewerRaw {
                let target = ProfileID(followingID)
                if FollowMutationCoordinator.shared.isFollowing(viewer: viewerID, target: target) {
#if DEBUG
                    RelationshipRealtimeDebugLog.relationshipEchoIgnored(
                        reason: "already_following",
                        detail: "\(viewerRaw)->\(followingID)"
                    )
#endif
                } else {
                    FollowMutationCoordinator.shared.applyEdgeChange(
                        viewer: viewerID,
                        target: target,
                        isFollowing: true
                    )
                }
                await syncFollowingFeedRoutes(viewerID: viewerID)
#if DEBUG
                RelationshipRealtimeDebugLog.relationshipPatch(
                    kind: "insert_outgoing",
                    viewerID: viewerRaw,
                    followerID: followerID,
                    followingID: followingID
                )
#endif
            } else if followingID == viewerRaw {
                FollowMutationCoordinator.shared.applyIncomingFollowAccepted(
                    owner: viewerID,
                    requester: ProfileID(followerID)
                )
#if DEBUG
                RelationshipRealtimeDebugLog.relationshipPatch(
                    kind: "insert_incoming",
                    viewerID: viewerRaw,
                    followerID: followerID,
                    followingID: followingID
                )
#endif
            }
        case .delete:
            if followerID == viewerRaw {
                let target = ProfileID(followingID)
                FollowMutationCoordinator.shared.applyEdgeChange(
                    viewer: viewerID,
                    target: target,
                    isFollowing: false
                )
                await syncFollowingFeedRoutes(viewerID: viewerID)
#if DEBUG
                RelationshipRealtimeDebugLog.relationshipPatch(
                    kind: "delete_outgoing",
                    viewerID: viewerRaw,
                    followerID: followerID,
                    followingID: followingID
                )
#endif
            } else if followingID == viewerRaw {
                FollowMutationCoordinator.shared.applyFollowerRemoved(
                    owner: viewerID,
                    follower: ProfileID(followerID)
                )
#if DEBUG
                RelationshipRealtimeDebugLog.relationshipPatch(
                    kind: "delete_incoming",
                    viewerID: viewerRaw,
                    followerID: followerID,
                    followingID: followingID
                )
#endif
            }
        case .update:
            break
        }
    }

    private func handleFollowRequestSignal(
        _ signal: MessageRealtimeSignal,
        viewerID: ProfileID,
        asRequester: Bool
    ) async {
        guard let payload = signal.recordPayload,
              let record = PostgresChangeRecordCodec.dictionary(from: payload)
        else { return }
        let requesterID = (record["requester_id"] as? String) ?? ""
        let targetID = (record["target_id"] as? String) ?? ""
        let status = (record["status"] as? String) ?? "pending"
        guard !requesterID.isEmpty, !targetID.isEmpty else { return }

        let eventKey = "follow_requests:\(signal.kind.rawValue):\(requesterID):\(targetID)"
        guard claimEvent(eventKey) else { return }

        switch signal.kind {
        case .insert where status == "pending":
            if asRequester, requesterID == viewerID.rawValue {
                FollowMutationCoordinator.shared.applyFollowRequestPresentation(
                    viewer: viewerID,
                    target: ProfileID(targetID),
                    isRequested: true
                )
#if DEBUG
                RelationshipRealtimeDebugLog.followRequestPatch(
                    action: "insert_outgoing",
                    requesterID: requesterID,
                    targetID: targetID
                )
#endif
            }
        case .delete:
            if asRequester, requesterID == viewerID.rawValue {
                FollowMutationCoordinator.shared.applyFollowRequestPresentation(
                    viewer: viewerID,
                    target: ProfileID(targetID),
                    isRequested: false
                )
#if DEBUG
                RelationshipRealtimeDebugLog.followRequestPatch(
                    action: "delete_outgoing",
                    requesterID: requesterID,
                    targetID: targetID
                )
#endif
            } else if !asRequester, targetID == viewerID.rawValue {
                // Declined/cancelled incoming request — Activity notification DELETE handles inbox.
#if DEBUG
                RelationshipRealtimeDebugLog.followRequestPatch(
                    action: "delete_incoming",
                    requesterID: requesterID,
                    targetID: targetID
                )
#endif
            }
        default:
            break
        }
    }

    private func claimEvent(_ key: String) -> Bool {
        if seenEventKeys.contains(key) { return false }
        seenEventKeys.insert(key)
        if seenEventKeys.count > maxSeenEventKeys {
            for key in seenEventKeys.prefix(maxSeenEventKeys / 4) {
                seenEventKeys.remove(key)
            }
        }
        return true
    }

    private func syncFollowingFeedRoutes(viewerID: ProfileID) async {
        guard await SessionFollowingStore.shared.isComplete(viewerID: viewerID.rawValue) else {
#if DEBUG
            RelationshipRealtimeDebugLog.followingRouteSync(added: 0, removed: 0, complete: false)
#endif
            return
        }
        await SocialEntityRealtimeSession.shared.syncFollowingAuthorsFromSession(viewerID: viewerID)
#if DEBUG
        RelationshipRealtimeDebugLog.followingRouteSync(added: 0, removed: 0, complete: true)
#endif
    }

#if DEBUG
    func testing_handleFollowerSignal(_ signal: MessageRealtimeSignal, viewerID: ProfileID) async {
        await handleFollowerSignal(signal, viewerID: viewerID)
    }
#endif
}
