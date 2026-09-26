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

/// Room live — message (+ optional presence) streams sharing one consumer.
nonisolated struct RoomLiveWatchStreams: Sendable {
    var messages: AsyncStream<MessageRealtimeSignal>
    var presence: AsyncStream<[RoomPresenceWireUser]>
    var consumer: RealtimeRouteConsumerHandle
}
