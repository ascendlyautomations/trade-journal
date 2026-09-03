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
        lock.unlock()
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
        lock.unlock()
    }

    /// Testing / DEBUG — current retain count for a channel.
    func retainCount(for channel: RealtimeChannelID) -> Int {
        lock.lock(); defer { lock.unlock() }
        return retainCounts[channel] ?? 0
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

    /// App foreground — reconnect socket and rejoin active watches if the WS died.
    func resumeIfNeeded() {
        guard isActive else { return }
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

    /// Web `subscribeCommunityRoomLiveChannel` — messages, reactions, optional presence track.
    func watchRoomLive(
        roomID: RoomID,
        accessToken: String?,
        presenceTrack: RoomPresenceTrackConfig?
    ) -> RoomLiveWatchStreams {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return RoomLiveWatchStreams(
                messages: AsyncStream { $0.finish() },
                presence: AsyncStream { $0.finish() }
            )
        }
        return live.watchRoomLive(
            roomID: roomID.rawValue,
            accessToken: accessToken,
            presenceTrack: presenceTrack
        )
    }

    func stopWatchingRoomMessages(roomID: RoomID) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingRoomMessages(roomID: roomID.rawValue)
    }

    func stopWatchingRoomLive(roomID: RoomID) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingRoomLive(roomID: roomID.rawValue)
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

    func watchMemberRoomMembership(
        roomIDs: [String],
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchMemberRoomMembership(roomIDs: roomIDs, accessToken: accessToken)
    }

    func stopWatchingMemberRoomMembership() async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingMemberRoomMembership()
    }

    /// Inbox — idle until `messages` arrive for loaded DM conversations.
    func watchInboxConversationMessages(
        conversationIDs: [String],
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchInboxConversationMessages(
            conversationIDs: conversationIDs,
            accessToken: accessToken
        )
    }

    func stopWatchingInboxConversationMessages() async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingInboxConversationMessages()
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

    /// Activity — idle until `notifications` postgres_changes for the viewer.
    func watchNotifications(userID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchNotifications(userID: userID, accessToken: accessToken)
    }

    func stopWatchingNotifications(userID: String) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingNotifications(userID: userID)
    }

    func watchViewerProfile(userID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchViewerProfile(userID: userID, accessToken: accessToken)
    }

    func stopWatchingViewerProfile(userID: String) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingViewerProfile(userID: userID)
    }

    func watchTraderDailyCheckIns(userID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchTraderDailyCheckIns(userID: userID, accessToken: accessToken)
    }

    func stopWatchingTraderDailyCheckIns(userID: String) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingTraderDailyCheckIns(userID: userID)
    }

    /// Detail comments — `comment_likes` postgres_changes for visible ids.
    func watchCommentLikes(
        source: CommentLikeSource,
        commentIDs: [String],
        accessToken: String?
    ) -> AsyncStream<CommentLikeRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchCommentLikes(
            source: source,
            commentIDs: commentIDs,
            accessToken: accessToken
        )
    }

    func stopWatchingCommentLikes(
        source: CommentLikeSource,
        commentIDs: [String]
    ) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingCommentLikes(source: source, commentIDs: commentIDs)
    }

    /// Detail comments — `UPDATE` postgres_changes for `pinned` on the content's comment table.
    func watchCommentPinUpdates(
        target: InteractionTarget,
        accessToken: String?
    ) -> AsyncStream<CommentPinRealtimeSignal> {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else {
            return AsyncStream { $0.finish() }
        }
        return live.watchCommentPinUpdates(target: target, accessToken: accessToken)
    }

    func stopWatchingCommentPinUpdates(target: InteractionTarget) async {
        guard let live = realtime as? LiveSupabaseRealtimeProvider else { return }
        await live.stopWatchingCommentPinUpdates(target: target)
    }
}
