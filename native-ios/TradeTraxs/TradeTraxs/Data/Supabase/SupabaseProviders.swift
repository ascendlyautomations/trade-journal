import Foundation
import Synchronization

/// Opaque handle for the configured Supabase project client.
nonisolated protocol SupabaseClientProviding: Sendable {
    var isConfigured: Bool { get }
    var projectURL: URL? { get }
}

nonisolated protocol SupabaseAuthProviding: Sendable {
    func currentAccessToken() async throws -> String?
}

nonisolated protocol SupabaseStorageProviding: Sendable {
    func publicURL(bucket: String, path: String) -> URL?
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
    func delete(bucket: String, path: String) async throws
}

nonisolated protocol SupabaseRealtimeProviding: Sendable {
    var isConnected: Bool { get }
    func connect() async throws
    func disconnect() async
}

nonisolated protocol SupabaseRPCProviding: Sendable {
    func invoke(functionName: String, parameters: [String: String]) async throws -> Data
}

nonisolated protocol SupabaseEdgeFunctionProviding: Sendable {
    func invoke(name: String, body: Data?) async throws -> Data
}

// Deliverable-facing names.
typealias SupabaseClientProvider = SupabaseClientProviding
typealias SupabaseAuthProvider = SupabaseAuthProviding
typealias SupabaseStorageProvider = SupabaseStorageProviding
typealias SupabaseRealtimeProvider = SupabaseRealtimeProviding
typealias SupabaseRPCProvider = SupabaseRPCProviding
typealias SupabaseEdgeFunctionProvider = SupabaseEdgeFunctionProviding

/// Production Supabase client provider — single configured project, lazy readiness.
nonisolated struct LiveSupabaseClientProvider: SupabaseClientProviding {
    let configuration: AppConfiguration

    var isConfigured: Bool { configuration.isSupabaseConfigured }
    var projectURL: URL? { configuration.supabaseURL }
}

nonisolated struct SessionBackedSupabaseAuthProvider: SupabaseAuthProviding {
    private let session: any SessionProviding

    init(session: any SessionProviding) {
        self.session = session
    }

    func currentAccessToken() async throws -> String? {
        await session.accessToken
    }
}

nonisolated struct LiveSupabaseStorageProvider: SupabaseStorageProviding {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func publicURL(bucket: String, path: String) -> URL? {
        guard let base = transport.configuration.supabaseURL else { return nil }
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        // String concat — `appendingPathComponent` percent-encodes `/` in multi-segment paths
        // (e.g. `{userId}/{timestamp}-file.jpg`) and breaks public object URLs.
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: "\(root)/storage/v1/object/public/\(bucket)/\(cleaned)")
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        _ = try await transport.send(
            host: .supabaseStorage,
            path: "/storage/v1/object/\(bucket)/\(cleaned)",
            method: .post,
            headers: [
                "Content-Type": contentType,
                "x-upsert": "true",
            ],
            body: data
        )
        return cleaned
    }

    func download(bucket: String, path: String) async throws -> Data {
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let response = try await transport.send(
            host: .supabaseStorage,
            path: "/storage/v1/object/\(bucket)/\(cleaned)",
            method: .get
        )
        return response.data
    }

    func delete(bucket: String, path: String) async throws {
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        struct Body: Encodable { var prefixes: [String] }
        let body = try transport.encodeJSON(Body(prefixes: [cleaned]))
        _ = try await transport.send(
            host: .supabaseStorage,
            path: "/storage/v1/object/\(bucket)",
            method: .delete,
            body: body
        )
    }
}

/// Realtime websocket + shared `postgres_changes` joins for DMs and Trade Rooms.
nonisolated final class LiveSupabaseRealtimeProvider: SupabaseRealtimeProviding, @unchecked Sendable {
    private struct PostgresChangeBinding: Sendable {
        var table: String
        var filter: String
        var routeColumn: String
        var emitsReactionEvents: Bool
        var emitsCommentLikeEvents: Bool = false
        var emitsCommentPinEvents: Bool = false
    }

    private struct CommentLikeWatchSpec: Sendable {
        var topic: String
        var routeKey: String
        var filter: String
        var source: String
        var visibleCommentIDs: Set<String>
    }

    private struct WatchSpec: Sendable {
        var topic: String
        var routeKey: String
        var bindings: [PostgresChangeBinding]
        /// Non-empty enables Realtime Presence on the same channel (web `room-live-${id}`).
        var presenceKey: String? = nil
    }

    private let configuration: AppConfiguration
    private let lock = Mutex(())
    private var webSocketTask: URLSessionWebSocketTask?
    private var _isConnected = false
    private let session: URLSession
    private var receiveLoopRunning = false
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// When true, receive-loop death must not auto-reconnect (explicit ``disconnect``).
    private var intentionalDisconnect = false
    private var refCounter = 0
    private var continuations: [String: [AsyncStream<MessageRealtimeSignal>.Continuation]] = [:]
    private var presenceContinuations: [String: [AsyncStream<[RoomPresenceWireUser]>.Continuation]] = [:]
    private var joinedTopics: Set<String> = []
    private var specsByRouteKey: [String: WatchSpec] = [:]
    private var accessTokensByRouteKey: [String: String?] = [:]
    private var presenceTrackConfigByRouteKey: [String: RoomPresenceTrackConfig] = [:]
    private var presenceTrackedByRouteKey: [String: Bool] = [:]
    /// Ephemeral Phoenix presence state keyed by topic — never persisted.
    private var presenceStateByTopic: [String: [String: [[String: Any]]]] = [:]
    private var commentLikeContinuations: [String: [AsyncStream<CommentLikeRealtimeSignal>.Continuation]] = [:]
    private var commentLikeSpecsByRouteKey: [String: CommentLikeWatchSpec] = [:]
    private var commentPinContinuations: [String: [AsyncStream<CommentPinRealtimeSignal>.Continuation]] = [:]

    init(configuration: AppConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.session = urlSession
    }

    private func withLocked<R>(_ body: () -> R) -> R {
        lock.withLock { _ in body() }
    }

    var isConnected: Bool {
        withLocked { _isConnected }
    }

    func connect() async throws {
        guard configuration.isSupabaseConfigured,
              let base = configuration.supabaseURL,
              let anon = configuration.supabaseAnonKey
        else {
            throw AppError.authentication(.notConfigured)
        }

        var components = URLComponents(
            url: base.appendingPathComponent("realtime/v1/websocket"),
            resolvingAgainstBaseURL: false
        )
        // URLSessionWebSocketTask requires ws/wss — map https → wss (http → ws).
        if components?.scheme?.lowercased() == "https" {
            components?.scheme = "wss"
        } else if components?.scheme?.lowercased() == "http" {
            components?.scheme = "ws"
        }
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: anon),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components?.url else {
            throw AppError.unknown(message: "Invalid realtime URL")
        }

        let task = session.webSocketTask(with: url)
        task.resume()
        withLocked {
        intentionalDisconnect = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = task
        _isConnected = true
        }
        startReceiveLoopIfNeeded()
        startHeartbeat()
    }

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        withLocked {
        intentionalDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        _isConnected = false
        receiveLoopRunning = false
        for values in continuations.values {
            for continuation in values {
                continuation.finish()
            }
        }
        for values in presenceContinuations.values {
            for continuation in values {
                continuation.finish()
            }
        }
        continuations.removeAll()
        presenceContinuations.removeAll()
        joinedTopics.removeAll()
        specsByRouteKey.removeAll()
        accessTokensByRouteKey.removeAll()
        presenceTrackConfigByRouteKey.removeAll()
        presenceTrackedByRouteKey.removeAll()
        presenceStateByTopic.removeAll()
        for values in commentLikeContinuations.values {
            for continuation in values {
                continuation.finish()
            }
        }
        commentLikeContinuations.removeAll()
        commentLikeSpecsByRouteKey.removeAll()
        for values in commentPinContinuations.values {
            for continuation in values {
                continuation.finish()
            }
        }
        commentPinContinuations.removeAll()
        }
    }

    /// Foreground / network recovery — reconnect and rejoin active watches without
    /// finishing product streams (avoids duplicate subscriptions at the domain layer).
    func resumeAfterForeground() async {
        let (connected, hasSpecs) = withLocked {
            (_isConnected, !specsByRouteKey.isEmpty)
        }
        if connected { return }
        if hasSpecs {
            await reconnectAndRejoin()
        } else {
            try? await connect()
        }
    }

    /// Web Community `room-live-${id}` topic — messages + reactions (no presence track).
    func watchRoomMessages(roomID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        let streams = watchRoomLive(roomID: roomID, accessToken: accessToken, presenceTrack: nil)
        return streams.messages
    }

    func stopWatchingRoomMessages(roomID: String) async {
        await stopWatchingRoomLive(roomID: roomID)
    }

    /// Web `subscribeCommunityRoomLiveChannel` — messages, reactions, and optional presence.
    func watchRoomLive(
        roomID: String,
        accessToken: String?,
        presenceTrack: RoomPresenceTrackConfig?
    ) -> RoomLiveWatchStreams {
        let routeKey = "room:\(roomID)"
        let spec = WatchSpec(
            topic: "realtime:room-live-\(roomID)",
            routeKey: routeKey,
            bindings: [
                PostgresChangeBinding(
                    table: "room_messages",
                    filter: "room_id=eq.\(roomID)",
                    routeColumn: "room_id",
                    emitsReactionEvents: false
                ),
                PostgresChangeBinding(
                    table: "room_message_reactions",
                    filter: "room_id=eq.\(roomID)",
                    routeColumn: "room_id",
                    emitsReactionEvents: true
                ),
            ],
            presenceKey: presenceTrack?.presenceKey
        )

        let messages = AsyncStream<MessageRealtimeSignal> { continuation in
            Task {
                try? await self.ensureConnected()
                let needsJoin = self.withLocked {
                    self.continuations[routeKey, default: []].append(continuation)
                    self.specsByRouteKey[routeKey] = spec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    if let presenceTrack {
                        self.presenceTrackConfigByRouteKey[routeKey] = presenceTrack
                    } else {
                        self.presenceTrackConfigByRouteKey.removeValue(forKey: routeKey)
                    }
                    let needsJoin = !self.joinedTopics.contains(spec.topic)
                    if needsJoin {
                        self.joinedTopics.insert(spec.topic)
                    }
                    return needsJoin
                }
                if needsJoin {
                    await self.joinChannel(spec, accessToken: accessToken)
                } else if presenceTrack != nil {
                    await self.trackRoomPresenceIfNeeded(routeKey: routeKey, topic: spec.topic)
                }
                continuation.onTermination = { _ in }
            }
        }

        let presence = AsyncStream<[RoomPresenceWireUser]> { continuation in
            Task {
                try? await self.ensureConnected()
                let joinState = self.withLocked { () -> (needsJoin: Bool, snapshot: [String: [[String: Any]]]?) in
                    self.presenceContinuations[routeKey, default: []].append(continuation)
                    self.specsByRouteKey[routeKey] = spec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    if let presenceTrack {
                        self.presenceTrackConfigByRouteKey[routeKey] = presenceTrack
                    }
                    let needsJoin = !self.joinedTopics.contains(spec.topic)
                    if needsJoin {
                        self.joinedTopics.insert(spec.topic)
                    }
                    let snapshot = self.presenceStateByTopic[spec.topic]
                    return (needsJoin, snapshot)
                }
                let needsJoin = joinState.needsJoin
                let snapshot = joinState.snapshot
                if needsJoin {
                    await self.joinChannel(spec, accessToken: accessToken)
                } else if presenceTrack != nil {
                    await self.trackRoomPresenceIfNeeded(routeKey: routeKey, topic: spec.topic)
                }
                if let snapshot {
                    continuation.yield(RoomPresenceSemantics.dedupeByUserID(snapshot))
                }
                continuation.onTermination = { _ in }
            }
        }

        return RoomLiveWatchStreams(messages: messages, presence: presence)
    }

    func stopWatchingRoomLive(roomID: String) async {
        await stopWatch(routeKey: "room:\(roomID)")
    }

    /// Web DM thread `messages` filter `conversation_id=eq.${id}`.
    func watchConversationMessages(
        conversationID: String,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:dm-\(conversationID)",
                routeKey: "dm:\(conversationID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "messages",
                        filter: "conversation_id=eq.\(conversationID)",
                        routeColumn: "conversation_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingConversationMessages(conversationID: String) async {
        await stopWatch(routeKey: "dm:\(conversationID)")
    }

    /// Inbox read-cursor sync — `conversation_member_preferences` for the signed-in user.
    /// `MessageRealtimeSignal.conversationID` carries the affected conversation.
    func watchConversationReadCursors(
        userID: String,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:dm-read-\(userID)",
                routeKey: "dm-read:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "conversation_member_preferences",
                        filter: "user_id=eq.\(userID)",
                        routeColumn: "conversation_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingConversationReadCursors(userID: String) async {
        await stopWatch(routeKey: "dm-read:\(userID)")
    }

    /// Inbox — `room_messages` for the viewer's member rooms (unread bump when not open).
    func watchMemberRoomMessages(
        roomIDs: [String],
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        let sorted = Array(Set(roomIDs)).sorted()
        let filter: String
        if sorted.count == 1 {
            filter = "room_id=eq.\(sorted[0])"
        } else {
            filter = "room_id=in.(\(sorted.joined(separator: ",")))"
        }
        return watch(
            WatchSpec(
                topic: "realtime:member-rooms",
                routeKey: "member-rooms",
                bindings: [
                    PostgresChangeBinding(
                        table: "room_messages",
                        filter: filter,
                        routeColumn: "room_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingMemberRoomMessages() async {
        await stopWatch(routeKey: "member-rooms")
    }

    /// Member room cards — `room_members` insert/update/delete for visible rooms.
    func watchMemberRoomMembership(
        roomIDs: [String],
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        let sorted = Array(Set(roomIDs)).sorted()
        guard !sorted.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        let filter: String
        if sorted.count == 1 {
            filter = "room_id=eq.\(sorted[0])"
        } else {
            filter = "room_id=in.(\(sorted.joined(separator: ",")))"
        }
        return watch(
            WatchSpec(
                topic: "realtime:member-room-membership",
                routeKey: "member-room-membership",
                bindings: [
                    PostgresChangeBinding(
                        table: "room_members",
                        filter: filter,
                        routeColumn: "room_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingMemberRoomMembership() async {
        await stopWatch(routeKey: "member-room-membership")
    }

    /// Inbox — `messages` for loaded DM conversations (preview + reorder when not in thread).
    func watchInboxConversationMessages(
        conversationIDs: [String],
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        let sorted = Array(Set(conversationIDs)).sorted()
        guard !sorted.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        let filter: String
        if sorted.count == 1 {
            filter = "conversation_id=eq.\(sorted[0])"
        } else {
            filter = "conversation_id=in.(\(sorted.joined(separator: ",")))"
        }
        return watch(
            WatchSpec(
                topic: "realtime:inbox-dms",
                routeKey: "inbox-dms",
                bindings: [
                    PostgresChangeBinding(
                        table: "messages",
                        filter: filter,
                        routeColumn: "conversation_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingInboxConversationMessages() async {
        await stopWatch(routeKey: "inbox-dms")
    }

    /// Inbox read-cursor sync — `room_members` for the signed-in user.
    func watchRoomReadCursors(
        userID: String,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:room-read-\(userID)",
                routeKey: "room-read:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "room_members",
                        filter: "user_id=eq.\(userID)",
                        routeColumn: "room_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingRoomReadCursors(userID: String) async {
        await stopWatch(routeKey: "room-read:\(userID)")
    }

    /// Home Feed — idle until `posts` postgres_changes arrive (web Community feed path).
    func watchFeedPosts(accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:feed-posts",
                routeKey: "feed-posts",
                bindings: [
                    PostgresChangeBinding(
                        table: "posts",
                        filter: "id=neq.00000000-0000-0000-0000-000000000000",
                        routeColumn: "id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingFeedPosts() async {
        await stopWatch(routeKey: "feed-posts")
    }

    /// Activity inbox — idle until `notifications` postgres_changes for the viewer.
    func watchNotifications(userID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:notifications-\(userID)",
                routeKey: "notifications:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "notifications",
                        filter: "user_id=eq.\(userID)",
                        routeColumn: "user_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingNotifications(userID: String) async {
        await stopWatch(routeKey: "notifications:\(userID)")
    }

    /// Viewer profile row — cross-device onboarding completion.
    func watchViewerProfile(userID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:viewer-profile-\(userID)",
                routeKey: "viewer-profile:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "profiles",
                        filter: "id=eq.\(userID)",
                        routeColumn: "id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingViewerProfile(userID: String) async {
        await stopWatch(routeKey: "viewer-profile:\(userID)")
    }

    /// Daily psychology check-in — postgres_changes for the signed-in user.
    func watchTraderDailyCheckIns(userID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:trader-daily-check-ins-\(userID)",
                routeKey: "trader-daily-check-ins:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "trader_daily_check_ins",
                        filter: "user_id=eq.\(userID)",
                        routeColumn: "user_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingTraderDailyCheckIns(userID: String) async {
        await stopWatch(routeKey: "trader-daily-check-ins:\(userID)")
    }

    /// Web `useCommentLikes` — `comment_likes` postgres_changes for visible comment ids.
    func watchCommentLikes(
        source: CommentLikeSource,
        commentIDs: [String],
        accessToken: String?
    ) -> AsyncStream<CommentLikeRealtimeSignal> {
        let unique = Array(Set(commentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        guard !unique.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        let filter = CommentLikeSemantics.realtimeFilter(source: source, commentIDs: unique)
        let routeKey = "comment-likes:\(CommentLikeSemantics.stableRouteSuffix(source: source, commentIDs: unique))"
        let topic = "realtime:\(routeKey)"

        return AsyncStream { continuation in
            Task {
                try? await self.ensureConnected()
                let spec = CommentLikeWatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    filter: filter,
                    source: source.rawValue,
                    visibleCommentIDs: Set(unique)
                )
                let joinSpec = WatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    bindings: [
                        PostgresChangeBinding(
                            table: "comment_likes",
                            filter: filter,
                            routeColumn: "comment_id",
                            emitsReactionEvents: false,
                            emitsCommentLikeEvents: true
                        ),
                    ]
                )
                let needsJoin = self.withLocked {
                    self.commentLikeContinuations[routeKey, default: []].append(continuation)
                    self.commentLikeSpecsByRouteKey[routeKey] = spec
                    self.specsByRouteKey[routeKey] = joinSpec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    let needsJoin = !self.joinedTopics.contains(topic)
                    if needsJoin {
                        self.joinedTopics.insert(topic)
                    }
                    return needsJoin
                }
                if needsJoin {
                    await self.joinChannel(joinSpec, accessToken: accessToken)
                }
                continuation.onTermination = { _ in }
            }
        }
    }

    func stopWatchingCommentLikes(
        source: CommentLikeSource,
        commentIDs: [String]
    ) async {
        let unique = Array(Set(commentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        guard !unique.isEmpty else { return }
        let routeKey = "comment-likes:\(CommentLikeSemantics.stableRouteSuffix(source: source, commentIDs: unique))"
        await stopCommentLikeWatch(routeKey: routeKey)
    }

    private func stopCommentLikeWatch(routeKey: String) async {
        let cleanup = withLocked { () -> ([AsyncStream<CommentLikeRealtimeSignal>.Continuation], WatchSpec?) in
            let conts = commentLikeContinuations.removeValue(forKey: routeKey) ?? []
            commentLikeSpecsByRouteKey.removeValue(forKey: routeKey)
            let spec = specsByRouteKey.removeValue(forKey: routeKey)
            accessTokensByRouteKey.removeValue(forKey: routeKey)
            if let topic = spec?.topic {
                joinedTopics.remove(topic)
            }
            return (conts, spec)
        }
        let conts = cleanup.0
        let spec = cleanup.1
        for continuation in conts {
            continuation.finish()
        }
        if let spec {
            await leaveChannel(topic: spec.topic)
        }
    }

    /// Web TradeSocialLayer — `UPDATE` on comment rows for `pinned` flips.
    func watchCommentPinUpdates(
        target: InteractionTarget,
        accessToken: String?
    ) -> AsyncStream<CommentPinRealtimeSignal> {
        let table = Self.commentTable(for: target.kind)
        let foreignKey = Self.commentForeignKey(for: target.kind)
        let filter = "\(foreignKey)=eq.\(target.id)"
        let routeKey = "comment-pin:\(target.kind.rawValue):\(target.id)"
        let topic = "realtime:\(routeKey)"

        return AsyncStream<CommentPinRealtimeSignal>(bufferingPolicy: .unbounded) { continuation in
            Task {
                try? await self.ensureConnected()
                let joinSpec = WatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    bindings: [
                        PostgresChangeBinding(
                            table: table,
                            filter: filter,
                            routeColumn: foreignKey,
                            emitsReactionEvents: false,
                            emitsCommentPinEvents: true
                        ),
                    ]
                )
                let needsJoin = self.withLocked {
                    self.commentPinContinuations[routeKey, default: []].append(continuation)
                    self.specsByRouteKey[routeKey] = joinSpec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    let needsJoin = !self.joinedTopics.contains(topic)
                    if needsJoin {
                        self.joinedTopics.insert(topic)
                    }
                    return needsJoin
                }
                if needsJoin {
                    await self.joinChannel(joinSpec, accessToken: accessToken)
                }
                continuation.onTermination = { _ in }
            }
        }
    }

    func stopWatchingCommentPinUpdates(target: InteractionTarget) async {
        let routeKey = "comment-pin:\(target.kind.rawValue):\(target.id)"
        let cleanup = withLocked { () -> ([AsyncStream<CommentPinRealtimeSignal>.Continuation], WatchSpec?) in
            let conts = commentPinContinuations.removeValue(forKey: routeKey) ?? []
            let spec = specsByRouteKey.removeValue(forKey: routeKey)
            accessTokensByRouteKey.removeValue(forKey: routeKey)
            if let topic = spec?.topic {
                joinedTopics.remove(topic)
            }
            return (conts, spec)
        }
        let conts = cleanup.0
        let spec = cleanup.1
        for continuation in conts {
            continuation.finish()
        }
        if let spec {
            await leaveChannel(topic: spec.topic)
        }
    }

    private static func commentTable(for kind: InteractionContentKind) -> String {
        switch kind {
        case .trade: return "trade_comments"
        case .profilePost: return "profile_post_comments"
        case .reel: return "reel_comments"
        case .feedPost: return "comments"
        case .achievement: return "achievement_post_comments"
        }
    }

    private static func commentForeignKey(for kind: InteractionContentKind) -> String {
        switch kind {
        case .trade: return "trade_id"
        case .profilePost: return "profile_post_id"
        case .reel: return "reel_id"
        case .feedPost: return "post_id"
        case .achievement: return "achievement_post_id"
        }
    }

    private func watch(
        _ spec: WatchSpec,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        AsyncStream { continuation in
            Task {
                try? await self.ensureConnected()
                let needsJoin = self.withLocked {
                    self.continuations[spec.routeKey, default: []].append(continuation)
                    self.specsByRouteKey[spec.routeKey] = spec
                    self.accessTokensByRouteKey[spec.routeKey] = accessToken
                    let needsJoin = !self.joinedTopics.contains(spec.topic)
                    if needsJoin {
                        self.joinedTopics.insert(spec.topic)
                    }
                    return needsJoin
                }
                if needsJoin {
                    await self.joinChannel(spec, accessToken: accessToken)
                }
                continuation.onTermination = { _ in }
            }
        }
    }

    private func stopWatch(routeKey: String) async {
        let cleanup = withLocked { () -> (
            [AsyncStream<MessageRealtimeSignal>.Continuation],
            [AsyncStream<[RoomPresenceWireUser]>.Continuation],
            WatchSpec?
        ) in
            let messageContinuations = continuations.removeValue(forKey: routeKey) ?? []
            let presenceConts = presenceContinuations.removeValue(forKey: routeKey) ?? []
            let spec = specsByRouteKey.removeValue(forKey: routeKey)
            accessTokensByRouteKey.removeValue(forKey: routeKey)
            presenceTrackConfigByRouteKey.removeValue(forKey: routeKey)
            presenceTrackedByRouteKey.removeValue(forKey: routeKey)
            if let topic = spec?.topic {
                joinedTopics.remove(topic)
                presenceStateByTopic.removeValue(forKey: topic)
            }
            return (messageContinuations, presenceConts, spec)
        }
        let messageContinuations = cleanup.0
        let presenceConts = cleanup.1
        let spec = cleanup.2
        for continuation in messageContinuations {
            continuation.finish()
        }
        for continuation in presenceConts {
            continuation.finish()
        }
        if let spec {
            if spec.presenceKey != nil {
                await untrackRoomPresence(topic: spec.topic)
            }
            await leaveChannel(topic: spec.topic)
        }
    }

    private func ensureConnected() async throws {
        if isConnected { return }
        try await connect()
    }

    private func nextRef() -> String {
        let value = withLocked {
            refCounter += 1
            return refCounter
        }
        return String(value)
    }

    private func joinChannel(_ spec: WatchSpec, accessToken: String?) async {
        let ref = nextRef()
        let postgresChanges: [[String: Any]] = spec.bindings.map { binding in
            [
                "event": "*",
                "schema": "public",
                "table": binding.table,
                "filter": binding.filter,
            ]
        }
        let presenceConfig: [String: Any]
        if let key = spec.presenceKey, !key.isEmpty {
            presenceConfig = ["key": key, "enabled": true]
        } else {
            presenceConfig = ["key": "", "enabled": false]
        }
        let config: [String: Any] = [
            "broadcast": ["ack": false, "self": false],
            "presence": presenceConfig,
            "postgres_changes": postgresChanges,
        ]
        var payload: [String: Any] = ["config": config]
        if let accessToken, !accessToken.isEmpty {
            payload["access_token"] = accessToken
        }
        await sendJSON([
            "topic": spec.topic,
            "event": "phx_join",
            "payload": payload,
            "ref": ref,
            "join_ref": ref,
        ])
    }

    private func leaveChannel(topic: String) async {
        let ref = nextRef()
        await sendJSON([
            "topic": topic,
            "event": "phx_leave",
            "payload": [:],
            "ref": ref,
        ])
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled else { break }
                let ref = self.nextRef()
                await self.sendJSON([
                    "topic": "phoenix",
                    "event": "heartbeat",
                    "payload": [:],
                    "ref": ref,
                ])
            }
        }
    }

    private func startReceiveLoopIfNeeded() {
        let shouldStart = withLocked { () -> Bool in
            if receiveLoopRunning {
                return false
            }
            receiveLoopRunning = true
            return true
        }
        guard shouldStart else { return }
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            let snapshot = withLocked { (webSocketTask, _isConnected) }
            let task = snapshot.0
            let connected = snapshot.1
            guard connected, let task else { break }
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleIncoming(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncoming(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let shouldReconnect = withLocked { () -> Bool in
            receiveLoopRunning = false
            _isConnected = false
            // Allow rejoin after reconnect — stale topic set would skip `phx_join`.
            joinedTopics.removeAll()
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            return !intentionalDisconnect && !specsByRouteKey.isEmpty
        }
        if shouldReconnect {
            scheduleReconnectAndRejoin()
        }
    }

    private func scheduleReconnectAndRejoin() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.reconnectAndRejoin()
        }
    }

    private func reconnectAndRejoin() async {
        let policy = ReconnectPolicy.default
        var attempt = 1
        while !Task.isCancelled, attempt <= policy.maximumAttempts {
            let snapshot = withLocked {
                (intentionalDisconnect, Array(specsByRouteKey.values), accessTokensByRouteKey)
            }
            let intentional = snapshot.0
            let specs = snapshot.1
            let tokens = snapshot.2
            guard !intentional, !specs.isEmpty else { return }

            do {
                try await connect()
                for spec in specs {
                    if Task.isCancelled { return }
                    let needsJoin = withLocked { () -> Bool in
                        let needsJoin = !joinedTopics.contains(spec.topic)
                        if needsJoin {
                            joinedTopics.insert(spec.topic)
                        }
                        presenceTrackedByRouteKey[spec.routeKey] = false
                        presenceStateByTopic.removeValue(forKey: spec.topic)
                        return needsJoin
                    }
                    if needsJoin {
                        await joinChannel(spec, accessToken: tokens[spec.routeKey] ?? nil)
                    } else if spec.presenceKey != nil {
                        await trackRoomPresenceIfNeeded(routeKey: spec.routeKey, topic: spec.topic)
                    }
                }
                return
            } catch {
                let delay = policy.delay(forAttempt: attempt)
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let event = object["event"] as? String ?? ""
        switch event {
        case "presence_state":
            handlePresenceState(object)
        case "presence_diff":
            handlePresenceDiff(object)
        case "phx_reply":
            handlePhxReply(object)
        case "postgres_changes", "INSERT", "UPDATE", "DELETE":
            handlePostgresChanges(object)
        default:
            break
        }
    }

    private func handlePhxReply(_ object: [String: Any]) {
        guard let payload = object["payload"] as? [String: Any],
              let status = payload["status"] as? String,
              status == "ok",
              let topic = object["topic"] as? String,
              topic.hasPrefix("realtime:room-live-")
        else { return }

        let routeKey = withLocked {
            specsByRouteKey.first(where: { $0.value.topic == topic })?.key
        }
        guard let routeKey else { return }
        Task { await trackRoomPresenceIfNeeded(routeKey: routeKey, topic: topic) }
    }

    private func handlePresenceState(_ object: [String: Any]) {
        guard let topic = object["topic"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }
        withLocked {
        var parsed: [String: [[String: Any]]] = [:]
        for (key, value) in payload {
            if let metas = value as? [[String: Any]] {
                parsed[key] = metas
            }
        }
        presenceStateByTopic[topic] = parsed
        }
        emitPresence(forTopic: topic)
    }

    private func handlePresenceDiff(_ object: [String: Any]) {
        guard let topic = object["topic"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }

        withLocked {
        var state = presenceStateByTopic[topic] ?? [:]
        if let joins = payload["joins"] as? [String: [[String: Any]]] {
            for (key, metas) in joins {
                state[key] = metas
            }
        }
        if let leaves = payload["leaves"] as? [String: [[String: Any]]] {
            for key in leaves.keys {
                state.removeValue(forKey: key)
            }
        }
        presenceStateByTopic[topic] = state
        }
        emitPresence(forTopic: topic)
    }

    private func emitPresence(forTopic topic: String) {
        let snapshot = withLocked { () -> (
            [String: [[String: Any]]],
            [AsyncStream<[RoomPresenceWireUser]>.Continuation]
        ) in
            let state = presenceStateByTopic[topic] ?? [:]
            let routeKey = specsByRouteKey.first(where: { $0.value.topic == topic })?.key
            let presenceConts = routeKey.flatMap { presenceContinuations[$0] } ?? []
            return (state, presenceConts)
        }
        let state = snapshot.0
        let presenceConts = snapshot.1
        let users = RoomPresenceSemantics.dedupeByUserID(state)
        for continuation in presenceConts {
            continuation.yield(users)
        }
    }

    private func trackRoomPresenceIfNeeded(routeKey: String, topic: String) async {
        let snapshot = withLocked {
            (presenceTrackConfigByRouteKey[routeKey], presenceTrackedByRouteKey[routeKey] ?? false)
        }
        let config = snapshot.0
        let alreadyTracked = snapshot.1
        guard let config, !alreadyTracked else { return }

        let enteredAt = ISO8601DateFormatter().string(from: Date())
        var trackPayload: [String: Any] = [
            "user_id": config.userID,
            "username": config.username,
            "entered_at": enteredAt,
        ]
        if let avatarURL = config.avatarURL {
            trackPayload["avatar_url"] = avatarURL
        }
        await sendJSON([
            "topic": topic,
            "event": "presence",
            "payload": [
                "event": "track",
                "payload": trackPayload,
            ],
            "ref": nextRef(),
        ])
        withLocked {
            presenceTrackedByRouteKey[routeKey] = true
        }
    }

    private func untrackRoomPresence(topic: String) async {
        await sendJSON([
            "topic": topic,
            "event": "presence",
            "payload": [
                "event": "untrack",
                "payload": [:] as [String: Any],
            ],
            "ref": nextRef(),
        ])
    }

    private func handlePostgresChanges(_ object: [String: Any]) {
        let event = object["event"] as? String ?? ""
        let payload = object["payload"] as? [String: Any] ?? [:]
        let dataPayload = (payload["data"] as? [String: Any]) ?? payload
        let type = (dataPayload["type"] as? String)
            ?? (dataPayload["eventType"] as? String)
            ?? event
        let record = (dataPayload["record"] as? [String: Any])
            ?? (dataPayload["new"] as? [String: Any])
        let oldRecord = dataPayload["old_record"] as? [String: Any]
            ?? dataPayload["old"] as? [String: Any]
        let messageID = (record?["id"] as? String)
            ?? (oldRecord?["id"] as? String)
        let table = (dataPayload["table"] as? String) ?? ""

        let kind: MessageRealtimeSignal.Kind
        switch type.uppercased() {
        case "INSERT": kind = .insert
        case "UPDATE": kind = .update
        case "DELETE": kind = .delete
        default: kind = .insert
        }

        let snapshot = withLocked {
            (
                Array(specsByRouteKey.values),
                continuations,
                commentLikeSpecsByRouteKey,
                commentLikeContinuations,
                commentPinContinuations
            )
        }
        let specs = snapshot.0
        let allContinuations = snapshot.1
        let likeSpecs = snapshot.2
        let allCommentLikeContinuations = snapshot.3
        let allCommentPinContinuations = snapshot.4

        if table == "comment_likes" {
            handleCommentLikeChanges(
                type: type,
                record: record,
                oldRecord: oldRecord,
                likeSpecs: likeSpecs,
                continuations: allCommentLikeContinuations
            )
            return
        }

        if type.uppercased() == "UPDATE" {
            handleCommentPinChanges(
                record: record,
                specs: specs,
                continuations: allCommentPinContinuations
            )
        }

        for spec in specs {
            guard let binding = spec.bindings.first(where: { $0.table == table }) else { continue }
            if binding.emitsCommentLikeEvents || binding.emitsCommentPinEvents { continue }
            let scope = (record?[binding.routeColumn] as? String)
                ?? (oldRecord?[binding.routeColumn] as? String)
            let scopedMatch: Bool
            if spec.routeKey.hasPrefix("dm-read:")
                || spec.routeKey.hasPrefix("room-read:")
                || spec.routeKey.hasPrefix("notifications:")
                || spec.routeKey == "member-rooms"
                || spec.routeKey == "inbox-dms"
                || spec.routeKey == "feed-posts"
            {
                scopedMatch = scope != nil
            } else {
                scopedMatch = scope.map { spec.routeKey.hasSuffix(":\($0)") } ?? false
            }
            guard scopedMatch else { continue }

            let signal: MessageRealtimeSignal
            if binding.emitsReactionEvents {
                let reactionMessageID = (record?["message_id"] as? String)
                    ?? (oldRecord?["message_id"] as? String)
                guard let reactionMessageID,
                      let reactionID = messageID,
                      let userID = (record?["user_id"] as? String) ?? (oldRecord?["user_id"] as? String),
                      let emoji = (record?["reaction"] as? String) ?? (oldRecord?["reaction"] as? String)
                else { continue }
                signal = MessageRealtimeSignal(
                    kind: kind,
                    messageID: reactionMessageID,
                    conversationID: scope,
                    reactionEvent: MessageRealtimeSignal.ReactionEvent(
                        reactionID: reactionID,
                        messageID: reactionMessageID,
                        userID: userID,
                        emoji: emoji
                    )
                )
            } else {
                signal = MessageRealtimeSignal(
                    kind: kind,
                    messageID: messageID,
                    conversationID: scope,
                    deletedForEveryone: Self.parseDeletedForEveryone(from: record)
                )
            }
            for continuation in allContinuations[spec.routeKey] ?? [] {
                continuation.yield(signal)
            }
        }
    }

    private func handleCommentLikeChanges(
        type: String,
        record: [String: Any]?,
        oldRecord: [String: Any]?,
        likeSpecs: [String: CommentLikeWatchSpec],
        continuations: [String: [AsyncStream<CommentLikeRealtimeSignal>.Continuation]]
    ) {
        let row = record ?? oldRecord
        guard let row else { return }
        let commentID = (row["comment_id"] as? String) ?? ""
        let userID = (row["user_id"] as? String) ?? ""
        let commentSource = (row["comment_source"] as? String) ?? ""
        guard !commentID.isEmpty, !userID.isEmpty else { return }

        let kind: CommentLikeSemantics.RealtimeMutationKind
        switch type.uppercased() {
        case "INSERT": kind = .insert
        case "DELETE": kind = .delete
        default: return
        }

        let signal = CommentLikeRealtimeSignal(
            kind: kind,
            commentID: commentID,
            userID: userID,
            commentSource: commentSource
        )

        for (routeKey, spec) in likeSpecs {
            guard spec.visibleCommentIDs.contains(commentID) else { continue }
            if !commentSource.isEmpty, spec.source != commentSource { continue }
            for continuation in continuations[routeKey] ?? [] {
                continuation.yield(signal)
            }
        }
    }

    private func handleCommentPinChanges(
        record: [String: Any]?,
        specs: [WatchSpec],
        continuations: [String: [AsyncStream<CommentPinRealtimeSignal>.Continuation]]
    ) {
        guard let record,
              let commentID = record["id"] as? String,
              !commentID.isEmpty
        else { return }
        let pinned = record["pinned"] as? Bool ?? false

        let signal = CommentPinRealtimeSignal(commentID: commentID, pinned: pinned)
        for spec in specs {
            guard spec.bindings.contains(where: { $0.emitsCommentPinEvents }) else { continue }
            for continuation in continuations[spec.routeKey] ?? [] {
                continuation.yield(signal)
            }
        }
    }

    private static func parseDeletedForEveryone(from record: [String: Any]?) -> Bool {
        guard let record else { return false }
        if let value = record["deleted_for_everyone"] as? Bool { return value }
        if let value = record["deleted_for_everyone"] as? NSNumber { return value.boolValue }
        if let value = record["deleted_for_everyone"] as? String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "t" || normalized == "1"
        }
        return false
    }

    private func sendJSON(_ object: [String: Any]) async {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8)
        else { return }
        let task = withLocked { webSocketTask }
        try? await task?.send(.string(text))
    }
}

/// Shared signal for DM `messages`, Trade Room `room_messages`, and room reactions.
nonisolated struct MessageRealtimeSignal: Sendable {
    enum Kind: String, Sendable {
        case insert
        case update
        case delete
    }

    struct ReactionEvent: Sendable, Equatable {
        var reactionID: String
        var messageID: String
        var userID: String
        var emoji: String
    }

    var kind: Kind
    var messageID: String?
    /// Populated from the postgres_changes filter column (e.g. `conversation_id`).
    var conversationID: String? = nil
    /// Soft-delete flag from `messages.deleted_for_everyone` on UPDATE payloads.
    var deletedForEveryone: Bool = false
    /// Present when the event originated from `room_message_reactions`.
    var reactionEvent: ReactionEvent? = nil
}

typealias RoomRealtimeSignal = MessageRealtimeSignal

/// Combined Trade Room live channel — messages/reactions + optional presence stream.
nonisolated struct RoomLiveWatchStreams: Sendable {
    var messages: AsyncStream<MessageRealtimeSignal>
    var presence: AsyncStream<[RoomPresenceWireUser]>
}

nonisolated struct LiveSupabaseRPCProvider: SupabaseRPCProviding {
    private let database: any SupabaseDatabaseExecuting

    init(database: any SupabaseDatabaseExecuting) {
        self.database = database
    }

    func invoke(functionName: String, parameters: [String: String]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: parameters, options: [])
        return try await database.rpcData(functionName: functionName, parametersJSON: data)
    }
}

nonisolated struct LiveSupabaseEdgeFunctionProvider: SupabaseEdgeFunctionProviding {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func invoke(name: String, body: Data?) async throws -> Data {
        let response = try await transport.send(
            host: .supabaseFunctions,
            path: "/functions/v1/\(name)",
            method: .post,
            body: body
        )
        return response.data
    }
}

/// Bundled Supabase integration points for repository constructors.
nonisolated struct SupabaseInfrastructure: Sendable {
    var client: any SupabaseClientProviding
    var auth: any SupabaseAuthProviding
    var storage: any SupabaseStorageProviding
    var realtime: any SupabaseRealtimeProviding
    var rpc: any SupabaseRPCProviding
    var edgeFunctions: any SupabaseEdgeFunctionProviding
    var database: any SupabaseDatabaseExecuting
    var transport: SupabaseTransport?

    static func make(
        appConfiguration: AppConfiguration,
        networking: NetworkingEnvironment,
        session: any SessionProviding
    ) -> SupabaseInfrastructure {
        let transport = SupabaseTransport(
            client: networking.client,
            requestBuilder: networking.requestBuilder,
            configuration: appConfiguration
        )
        let database = SupabaseDatabaseClient(transport: transport)
        let storage = LiveSupabaseStorageProvider(transport: transport)
        let realtime = LiveSupabaseRealtimeProvider(configuration: appConfiguration)
        return SupabaseInfrastructure(
            client: LiveSupabaseClientProvider(configuration: appConfiguration),
            auth: SessionBackedSupabaseAuthProvider(session: session),
            storage: storage,
            realtime: realtime,
            rpc: LiveSupabaseRPCProvider(database: database),
            edgeFunctions: LiveSupabaseEdgeFunctionProvider(transport: transport),
            database: database,
            transport: transport
        )
    }

    /// Unconfigured graph for isolated unit tests that do not touch the network.
    static let unconfigured = SupabaseInfrastructure(
        client: LiveSupabaseClientProvider(
            configuration: AppConfiguration(
                buildConfiguration: .debug,
                apiBaseURL: nil,
                supabaseURL: nil,
                supabaseAnonKey: nil,
                appDisplayName: "TradeTraxs"
            )
        ),
        auth: SessionBackedSupabaseAuthProvider(session: PlaceholderSessionProvider()),
        storage: UnconfiguredObjectStorageAdapter(),
        realtime: DisconnectedRealtimeProvider(),
        rpc: LiveSupabaseRPCProvider(database: UnconfiguredSupabaseDatabaseClient()),
        edgeFunctions: UnconfiguredEdgeAdapter(),
        database: UnconfiguredSupabaseDatabaseClient(),
        transport: nil
    )
}

private nonisolated struct DisconnectedRealtimeProvider: SupabaseRealtimeProviding {
    var isConnected: Bool { false }
    func connect() async throws { throw AppError.authentication(.notConfigured) }
    func disconnect() async {}
}

private nonisolated struct UnconfiguredObjectStorageAdapter: SupabaseStorageProviding {
    func publicURL(bucket: String, path: String) -> URL? {
        _ = (bucket, path)
        return nil
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        _ = (bucket, path, data, contentType)
        throw AppError.authentication(.notConfigured)
    }

    func download(bucket: String, path: String) async throws -> Data {
        _ = (bucket, path)
        throw AppError.authentication(.notConfigured)
    }

    func delete(bucket: String, path: String) async throws {
        _ = (bucket, path)
        throw AppError.authentication(.notConfigured)
    }
}

private nonisolated struct UnconfiguredEdgeAdapter: SupabaseEdgeFunctionProviding {
    func invoke(name: String, body: Data?) async throws -> Data {
        _ = (name, body)
        throw AppError.authentication(.notConfigured)
    }
}
