import Foundation

/// Stable identity for one logical Realtime watch consumer on a shared route.
nonisolated struct RealtimeRouteConsumerHandle: Sendable, Hashable {
    let id: UUID
    let routeKey: String
    /// DEBUG — short owner label (e.g. `GettingStarted`, `ProfileOnboarding`).
    let debugOwner: String?

    init(id: UUID = UUID(), routeKey: String, debugOwner: String? = nil) {
        self.id = id
        self.routeKey = routeKey
        self.debugOwner = debugOwner
    }
}

/// Postgres `MessageRealtimeSignal` watch — stream plus releasable consumer handle.
nonisolated struct RealtimeMessageWatch: Sendable {
    var events: AsyncStream<MessageRealtimeSignal>
    var consumer: RealtimeRouteConsumerHandle
}

/// Comment like watch bundle.
nonisolated struct RealtimeCommentLikeWatch: Sendable {
    var events: AsyncStream<CommentLikeRealtimeSignal>
    var consumer: RealtimeRouteConsumerHandle
}

/// Content engagement like watch bundle (Phase 10C).
nonisolated struct RealtimeContentLikeWatch: Sendable {
    var events: AsyncStream<ContentLikeRealtimeSignal>
    var consumer: RealtimeRouteConsumerHandle
}

/// Feed/Profile entity postgres_changes (Phase 10D).
nonisolated struct RealtimeSocialEntityWatch: Sendable {
    var events: AsyncStream<SocialEntityRealtimeEvent>
    var consumer: RealtimeRouteConsumerHandle
}

/// Comment pin watch bundle.
nonisolated struct RealtimeCommentPinWatch: Sendable {
    var events: AsyncStream<CommentPinRealtimeSignal>
    var consumer: RealtimeRouteConsumerHandle
}

/// Room live — message (+ optional presence) streams sharing one consumer.
nonisolated struct RoomLiveWatchStreams: Sendable {
    var messages: AsyncStream<MessageRealtimeSignal>
    var presence: AsyncStream<[RoomPresenceWireUser]>
    var consumer: RealtimeRouteConsumerHandle
}
