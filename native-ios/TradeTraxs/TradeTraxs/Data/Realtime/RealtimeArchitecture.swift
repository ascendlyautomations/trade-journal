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
}

nonisolated final class InMemoryChannelRegistry: ChannelRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var channels: Set<RealtimeChannelID> = []

    func registeredChannels() -> [RealtimeChannelID] {
        lock.lock(); defer { lock.unlock() }
        return Array(channels)
    }

    func register(_ channel: RealtimeChannelID) {
        lock.lock(); channels.insert(channel); lock.unlock()
    }

    func unregister(_ channel: RealtimeChannelID) {
        lock.lock(); channels.remove(channel); lock.unlock()
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
        for channel in registry.registeredChannels() {
            registry.unregister(channel)
        }
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
        Task { [weak self] in
            await self?.establishConnectionWithRetry()
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
        await subscriptions.unsubscribeAll()
        await realtime.disconnect()
    }

    var isConnected: Bool { realtime.isConnected }

    /// Web Community room channel — idle until `room_messages` postgres_changes arrive.
    func watchRoomMessages(roomID: RoomID, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchRoomMessages(roomID: roomID.rawValue, accessToken: accessToken)
    }

    func stopWatchingRoomMessages(roomID: RoomID) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingRoomMessages(roomID: roomID.rawValue)
    }

    /// Web DM thread — idle until `messages` postgres_changes arrive.
    func watchConversationMessages(
        conversationID: ConversationID,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchConversationMessages(
            conversationID: conversationID.rawValue,
            accessToken: accessToken
        )
    }

    func stopWatchingConversationMessages(conversationID: ConversationID) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingConversationMessages(conversationID: conversationID.rawValue)
    }

    /// Inbox — idle until `conversation_member_preferences` changes for the viewer.
    func watchConversationReadCursors(
        userID: String,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchConversationReadCursors(userID: userID, accessToken: accessToken)
    }

    func stopWatchingConversationReadCursors(userID: String) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingConversationReadCursors(userID: userID)
    }

    /// Inbox — idle until `room_messages` arrive for member rooms.
    func watchMemberRoomMessages(
        roomIDs: [String],
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchMemberRoomMessages(roomIDs: roomIDs, accessToken: accessToken)
    }

    func stopWatchingMemberRoomMessages() async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingMemberRoomMessages()
    }

    /// Inbox — idle until `room_members` read-cursor changes for the viewer.
    func watchRoomReadCursors(
        userID: String,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchRoomReadCursors(userID: userID, accessToken: accessToken)
    }

    func stopWatchingRoomReadCursors(userID: String) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingRoomReadCursors(userID: userID)
    }

    /// Home Feed — idle until `posts` postgres_changes arrive.
    func watchFeedPosts(accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchFeedPosts(accessToken: accessToken)
    }

    func stopWatchingFeedPosts() async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingFeedPosts()
    }
}
