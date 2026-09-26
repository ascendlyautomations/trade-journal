import Foundation

nonisolated enum RealtimeChannelKind: String, Sendable {
    case notifications
    case feed
    case conversation
    case room
    case profile
}

nonisolated struct RealtimeChannelID: Hashable, Sendable {
    var kind: RealtimeChannelKind
    var topic: String
}

nonisolated struct RealtimeEvent: Sendable {
    var channelID: RealtimeChannelID
    var name: String
    var payload: Data
    var receivedAt: Date
}

nonisolated protocol RealtimeEventMapping: Sendable {
    func map(_ event: RealtimeEvent) throws -> String
}

nonisolated struct DefaultRealtimeEventMapper: RealtimeEventMapping {
    func map(_ event: RealtimeEvent) throws -> String {
        "\(event.channelID.kind.rawValue):\(event.name)"
    }
}

nonisolated struct ReconnectPolicy: Sendable {
    var maximumAttempts: Int
    var baseDelay: TimeInterval
    var maximumDelay: TimeInterval

    static let `default` = ReconnectPolicy(
        maximumAttempts: 8,
        baseDelay: 0.5,
        maximumDelay: 30
    )

    func delay(forAttempt attempt: Int) -> TimeInterval {
        min(maximumDelay, baseDelay * pow(2, Double(max(0, attempt - 1))))
    }
}

nonisolated protocol ChannelRegistry: Sendable {
    func registeredChannels() -> [RealtimeChannelID]
    func register(_ channel: RealtimeChannelID)
    func unregister(_ channel: RealtimeChannelID)
    func clearAll()
}

nonisolated final class InMemoryChannelRegistry: ChannelRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var channels: Set<RealtimeChannelID> = []
    /// Refcounts so ephemeral view appear/disappear cycles do not drop session channels.
    private var retainCounts: [RealtimeChannelID: Int] = [:]

    func registeredChannels() -> [RealtimeChannelID] {
        lock.lock(); defer { lock.unlock() }
        return Array(channels)
    }

    func register(_ channel: RealtimeChannelID) {
        lock.lock()
        retainCounts[channel, default: 0] += 1
        channels.insert(channel)
        let refcount = retainCounts[channel] ?? 0
        let registered = channels.count
        lock.unlock()
        RealtimeLifecycleDebugLog.registrySubscribe(
            kind: channel.kind.rawValue,
            topic: channel.topic,
            refcount: refcount,
            registered: registered
        )
    }

    func unregister(_ channel: RealtimeChannelID) {
        lock.lock()
        let next = max(0, (retainCounts[channel] ?? 1) - 1)
        if next == 0 {
            retainCounts[channel] = nil
            channels.remove(channel)
        } else {
            retainCounts[channel] = next
        }
        let registered = channels.count
        lock.unlock()
        RealtimeLifecycleDebugLog.registryUnsubscribe(
            kind: channel.kind.rawValue,
            topic: channel.topic,
            refcount: next,
            registered: registered
        )
    }

    /// Testing / DEBUG — current retain count for a channel.
    func retainCount(for channel: RealtimeChannelID) -> Int {
        lock.lock(); defer { lock.unlock() }
        return retainCounts[channel] ?? 0
    }

    func clearAll() {
        lock.lock()
        channels = []
        retainCounts = [:]
        lock.unlock()
    }
}

nonisolated protocol SubscriptionManaging: Sendable {
    func subscribe(_ channel: RealtimeChannelID) async throws
    func unsubscribe(_ channel: RealtimeChannelID) async throws
    func unsubscribeAll() async
}

/// Registry-only subscription manager — product channels are not joined in Phase 4B.
nonisolated struct RegistrySubscriptionManager: SubscriptionManaging {
    private let registry: any ChannelRegistry

    init(registry: any ChannelRegistry) {
        self.registry = registry
    }

    func subscribe(_ channel: RealtimeChannelID) async throws {
        registry.register(channel)
    }

    func unsubscribe(_ channel: RealtimeChannelID) async throws {
        registry.unregister(channel)
    }

    func unsubscribeAll() async {
        registry.clearAll()
    }
}

/// Sole owner of long-lived realtime connection + channel registry (architecture §10).
nonisolated final class RealtimeHub: @unchecked Sendable {
    let registry: any ChannelRegistry
    let subscriptions: any SubscriptionManaging
    let eventMapper: any RealtimeEventMapping
    let reconnectPolicy: ReconnectPolicy
    private let realtime: any SupabaseRealtimeProviding
    private(set) var isActive: Bool = false

    init(
        realtime: any SupabaseRealtimeProviding,
        registry: any ChannelRegistry = InMemoryChannelRegistry(),
        eventMapper: any RealtimeEventMapping = DefaultRealtimeEventMapper(),
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.realtime = realtime
        self.registry = registry
        self.subscriptions = RegistrySubscriptionManager(registry: registry)
        self.eventMapper = eventMapper
        self.reconnectPolicy = reconnectPolicy
    }

    /// Boots connection infrastructure only — does not open product channels.
    func start() {
        guard !isActive else { return }
        isActive = true
        RealtimeLifecycleDebugLog.hubStart()
        Task { [weak self] in
            await self?.establishConnectionWithRetry()
        }
    }

    /// App foreground — reconnect socket and rejoin active watches if the WS died.
    func resumeIfNeeded() {
        guard isActive else { return }
        RealtimeLifecycleDebugLog.hubResumeIfNeeded()
        Task { [weak self] in
            guard let self else { return }
            if let live = self.realtime as? LiveSupabaseRealtimeProvider {
                await live.resumeAfterForeground()
            } else if !self.realtime.isConnected {
                await self.establishConnectionWithRetry()
            }
        }
    }

    private func establishConnectionWithRetry() async {
        var attempt = 1
        while isActive, attempt <= reconnectPolicy.maximumAttempts {
            do {
                try await realtime.connect()
                return
            } catch {
                let delay = reconnectPolicy.delay(forAttempt: attempt)
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stop() async {
        isActive = false
        RealtimeLifecycleDebugLog.hubStop()
        await subscriptions.unsubscribeAll()
        await realtime.disconnect()
    }

    var isConnected: Bool { realtime.isConnected }

    func realtimePressureSnapshot() -> SupabasePressureRealtimeSnapshot {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return SupabasePressureRealtimeSnapshot(
                sessionGeneration: 0,
                activeRoutes: 0,
                joinedTopics: 0,
                logicalConsumers: 0
            )
        }
        return live.realtimePressureSnapshot()
    }

    func awaitReconnectCompletionIfInFlight() async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.awaitReconnectCompletionIfInFlight()
    }

    /// Release one Realtime consumer without affecting peers on the same route.
    func releaseWatch(_ consumer: RealtimeRouteConsumerHandle?) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.releaseWatch(consumer)
    }

    private static func emptyMessageWatch(routeKey: String) -> RealtimeMessageWatch {
        RealtimeMessageWatch(
            events: AsyncStream { $0.finish() },
            consumer: RealtimeRouteConsumerHandle(routeKey: routeKey)
        )
    }

    /// Web Community room channel — idle until `room_messages` postgres_changes arrive.
    func watchRoomMessages(roomID: RoomID, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        watchRoomLive(roomID: roomID, accessToken: accessToken, presenceTrack: nil).messages
    }

    /// Web `subscribeCommunityRoomLiveChannel` — messages, reactions, optional presence track.
    func watchRoomLive(
        roomID: RoomID,
        accessToken: String?,
        presenceTrack: RoomPresenceTrackConfig?,
        debugOwner: String? = nil
    ) -> RoomLiveWatchStreams {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            let empty = Self.emptyMessageWatch(routeKey: "room:\(roomID.rawValue)")
            return RoomLiveWatchStreams(
                messages: empty.events,
                presence: AsyncStream { $0.finish() },
                consumer: empty.consumer
            )
        }
        return live.watchRoomLive(
            roomID: roomID.rawValue,
            accessToken: accessToken,
            presenceTrack: presenceTrack,
            debugOwner: debugOwner
        )
    }

    /// Web DM thread — idle until `messages` postgres_changes arrive.
    func watchConversationMessages(
        conversationID: ConversationID,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return Self.emptyMessageWatch(routeKey: "dm:\(conversationID.rawValue)")
        }
        return live.watchConversationMessages(
            conversationID: conversationID.rawValue,
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox read cursors — `conversation_member_preferences` (publication candidate; watch retained).
    func watchConversationReadCursors(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return Self.emptyMessageWatch(routeKey: "dm-read:\(userID)")
        }
        return live.watchConversationReadCursors(
            userID: userID,
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox — idle until `room_messages` arrive for member rooms.
    func watchMemberRoomMessages(
        roomIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return Self.emptyMessageWatch(routeKey: "member-rooms")
        }
        return live.watchMemberRoomMessages(
            roomIDs: roomIDs,
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox — idle until `messages` arrive for loaded DM conversations.
    func watchInboxConversationMessages(
        conversationIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return Self.emptyMessageWatch(routeKey: "inbox-dms")
        }
        return live.watchInboxConversationMessages(
            conversationIDs: conversationIDs,
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox room read cursors — `room_members` (publication candidate; watch retained).
    func watchRoomReadCursors(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return Self.emptyMessageWatch(routeKey: "room-read:\(userID)")
        }
        return live.watchRoomReadCursors(
            userID: userID,
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Activity — idle until `notifications` postgres_changes for the viewer.
    func watchNotifications(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return Self.emptyMessageWatch(routeKey: "notifications:\(userID)")
        }
        return live.watchNotifications(userID: userID, accessToken: accessToken, debugOwner: debugOwner)
    }

}
