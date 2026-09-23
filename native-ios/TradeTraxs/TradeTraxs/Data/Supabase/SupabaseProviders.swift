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
    func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String?
    ) async throws -> String
    func download(bucket: String, path: String) async throws -> Data
    func delete(bucket: String, path: String) async throws
}

extension SupabaseStorageProviding {
    func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        try await upload(
            bucket: bucket,
            path: path,
            data: data,
            contentType: contentType,
            cacheControl: nil
        )
    }
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

    func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String? = nil
    ) async throws -> String {
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var headers = [
            "Content-Type": contentType,
            "x-upsert": "true",
        ]
        if let cacheControl, !cacheControl.isEmpty {
            // Supabase Storage expects `cache-control: max-age=<seconds>` (matches supabase-js upload options).
            headers["cache-control"] = "max-age=\(cacheControl)"
        }
        if let jobID = UploadProgressContext.jobID {
            let endpoint = Endpoint(
                host: .supabaseStorage,
                path: "/storage/v1/object/\(bucket)/\(cleaned)",
                method: .post,
                queryItems: [],
                headers: headers,
                requiresAuthentication: true
            )
            let built = try transport.requestBuilder.makeRequest(endpoint: endpoint, body: data)
            let authenticated = try await transport.prepareRequest(built)
            var uploadRequest = authenticated.urlRequest
            uploadRequest.httpBody = nil
            uploadRequest.httpBodyStream = nil

            var attempt = 1
            let maxAttempts = 3
            while true {
                let (responseData, urlResponse) = try await StorageUploadProgressTransport.upload(
                    request: uploadRequest,
                    body: data,
                    progressJobID: jobID
                )
                if let http = urlResponse as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) {
                    break
                }
                let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
                let supabaseCode = StorageUploadDiagnostics.parseSupabaseCode(from: responseData)
                if attempt < maxAttempts, Self.isRetriableStorageUpload(status: status, supabaseCode: supabaseCode) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(min(attempt, 3)) * 500_000_000)
                    continue
                }
                if let mapped = NetworkErrorMapper().map(
                    data: responseData,
                    response: urlResponse,
                    error: nil
                ) {
                    throw SupabaseErrorMapping.mapNetwork(mapped)
                }
                throw AppError.unknown(message: "Upload failed.")
            }
        } else {
            _ = try await transport.send(
                host: .supabaseStorage,
                path: "/storage/v1/object/\(bucket)/\(cleaned)",
                method: .post,
                headers: headers,
                body: data
            )
        }
        return cleaned
    }

    private static func isRetriableStorageUpload(status: Int, supabaseCode: String?) -> Bool {
        if status == 544 { return true }
        if supabaseCode == "DatabaseTimeout" { return true }
        if (500 ... 599).contains(status) { return true }
        return false
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
        var emitsContentLikeEvents: Bool = false
        var emitsSocialEntityEvents: Bool = false
        var emitsCommentPinEvents: Bool = false
        /// Postgres change event filter (`*`, `UPDATE`, …).
        var postgresEvent: String = "*"
    }

    private struct CommentLikeWatchSpec: Sendable {
        var topic: String
        var routeKey: String
        var filter: String
        var source: String
        var visibleCommentIDs: Set<String>
    }

    private struct ContentLikeWatchSpec: Sendable {
        var topic: String
        var routeKey: String
        var filter: String
        var table: ContentLikeTable
        var visibleContentIDs: Set<String>
    }

    private struct SocialEntityWatchSpec: Sendable {
        var topic: String
        var routeKey: String
        var filter: String
        var table: SocialEntityRealtimeTable
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
    /// Bumped on session teardown — stale consumers never receive events after logout/switch.
    private var watchSessionGeneration: UInt64 = 0
    private struct MessageRouteConsumer {
        var sessionGeneration: UInt64
        var routeEpoch: UInt64
        var continuation: AsyncStream<MessageRealtimeSignal>.Continuation?
        var presenceContinuation: AsyncStream<[RoomPresenceWireUser]>.Continuation?
        var debugOwner: String?
        /// Room live registers message + optional presence — each stream end decrements before route leave.
        var openStreamsRemaining: Int
    }
    private struct CommentLikeRouteConsumer {
        var sessionGeneration: UInt64
        var routeEpoch: UInt64
        var continuation: AsyncStream<CommentLikeRealtimeSignal>.Continuation
    }
    private struct ContentLikeRouteConsumer {
        var sessionGeneration: UInt64
        var routeEpoch: UInt64
        var continuation: AsyncStream<ContentLikeRealtimeSignal>.Continuation
    }
    private struct SocialEntityRouteConsumer {
        var sessionGeneration: UInt64
        var routeEpoch: UInt64
        var continuation: AsyncStream<SocialEntityRealtimeEvent>.Continuation
    }
    private struct CommentPinRouteConsumer {
        var sessionGeneration: UInt64
        var routeEpoch: UInt64
        var continuation: AsyncStream<CommentPinRealtimeSignal>.Continuation
    }
    private var messageConsumersByRoute: [String: [UUID: MessageRouteConsumer]] = [:]
    private var joinedTopics: Set<String> = []
    private var specsByRouteKey: [String: WatchSpec] = [:]
    private var accessTokensByRouteKey: [String: String?] = [:]
    private var presenceTrackConfigByRouteKey: [String: RoomPresenceTrackConfig] = [:]
    private var presenceTrackedByRouteKey: [String: Bool] = [:]
    /// Ephemeral Phoenix presence state keyed by topic — never persisted.
    private var presenceStateByTopic: [String: [String: [[String: Any]]]] = [:]
    private var commentLikeConsumersByRoute: [String: [UUID: CommentLikeRouteConsumer]] = [:]
    private var commentLikeSpecsByRouteKey: [String: CommentLikeWatchSpec] = [:]
    private var contentLikeConsumersByRoute: [String: [UUID: ContentLikeRouteConsumer]] = [:]
    private var contentLikeSpecsByRouteKey: [String: ContentLikeWatchSpec] = [:]
    private var socialEntityConsumersByRoute: [String: [UUID: SocialEntityRouteConsumer]] = [:]
    private var socialEntitySpecsByRouteKey: [String: SocialEntityWatchSpec] = [:]
    private var commentPinConsumersByRoute: [String: [UUID: CommentPinRouteConsumer]] = [:]
    /// Bumped when a route's last consumer leaves — stale async retain/join work must not rejoin.
    private var routeEpochByKey: [String: UInt64] = [:]
    /// Consumers fully removed from the registry — duplicate releaseWatch is a no-op.
    private var releasedConsumerIDs: Set<UUID> = []
    #if DEBUG
    /// Registry-driven 0→1 joins only (excludes reconnect rejoin storms in unit tests).
    private var testingRegistryJoinCount = 0
    private var testingRegistryLeaveCount = 0
    private var testingTransportJoinCount = 0
    private var testingTransportLeaveCount = 0
    #endif

    init(configuration: AppConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.session = urlSession
    }

    private func withLocked<R>(_ body: () -> R) -> R {
        lock.withLock { _ in body() }
    }

    private struct RouteLifecycleSnapshot: Sendable {
        var activeRoutes: Int
        var joinedTopics: Int
    }

    private func routeLifecycleSnapshot(routeKey: String? = nil) -> RouteLifecycleSnapshot {
        withLocked {
            RouteLifecycleSnapshot(
                activeRoutes: specsByRouteKey.count,
                joinedTopics: joinedTopics.count
            )
        }
    }

    private func logicalConsumerCountLocked(routeKey: String) -> Int {
        if let consumers = messageConsumersByRoute[routeKey] {
            return consumers.count
        }
        if let consumers = commentLikeConsumersByRoute[routeKey] {
            return consumers.count
        }
        if let consumers = contentLikeConsumersByRoute[routeKey] {
            return consumers.count
        }
        if let consumers = socialEntityConsumersByRoute[routeKey] {
            return consumers.count
        }
        if let consumers = commentPinConsumersByRoute[routeKey] {
            return consumers.count
        }
        return 0
    }

    private func logicalConsumerCount(routeKey: String) -> Int {
        withLocked { logicalConsumerCountLocked(routeKey: routeKey) }
    }

    private func isTopicPhysicallyJoined(topic: String) -> Bool {
        withLocked { joinedTopics.contains(topic) }
    }

    private struct RouteConsumerRetainState {
        var isDuplicate: Bool
        var consumerCount: Int
        var sessionGeneration: UInt64
    }

    private enum RegistryJoinDecision {
        case abandoned
        case reuseExistingTopic
        case claimFirstJoin
    }

    private func consumerRouteEpochLocked(routeKey: String, consumerID: UUID) -> UInt64? {
        if let entry = messageConsumersByRoute[routeKey]?[consumerID] { return entry.routeEpoch }
        if let entry = commentLikeConsumersByRoute[routeKey]?[consumerID] { return entry.routeEpoch }
        if let entry = contentLikeConsumersByRoute[routeKey]?[consumerID] { return entry.routeEpoch }
        if let entry = socialEntityConsumersByRoute[routeKey]?[consumerID] { return entry.routeEpoch }
        if let entry = commentPinConsumersByRoute[routeKey]?[consumerID] { return entry.routeEpoch }
        return nil
    }

    /// Decide join vs reuse immediately before transport — avoids stale pre-await join flags.
    private func claimRegistryJoinLocked(
        routeKey: String,
        topic: String,
        consumerID: UUID
    ) -> RegistryJoinDecision {
        guard let consumerEpoch = consumerRouteEpochLocked(routeKey: routeKey, consumerID: consumerID) else {
            return .abandoned
        }
        guard consumerEpoch == routeEpochByKey[routeKey, default: 0] else {
            return .abandoned
        }
        let consumers = logicalConsumerCountLocked(routeKey: routeKey)
        guard consumers > 0 else { return .abandoned }
        if joinedTopics.contains(topic) { return .reuseExistingTopic }
        joinedTopics.insert(topic)
        return .claimFirstJoin
    }

    /// Atomically decide whether this route may physically leave (count already 0).
    private func claimRegistryLeaveLocked(routeKey: String, topic: String) -> Bool {
        guard logicalConsumerCountLocked(routeKey: routeKey) == 0 else { return false }
        guard joinedTopics.contains(topic) else { return false }
        joinedTopics.remove(topic)
        routeEpochByKey[routeKey, default: 0] &+= 1
        return true
    }

    private func noteConsumerFullyReleasedLocked(consumerID: UUID) {
        releasedConsumerIDs.insert(consumerID)
    }

    /// Registry retain + optional physical join — call after the consumer map mutation inside `withLocked`.
    private func applyRegistryRetainAndJoin(
        routeKey: String,
        topic: String,
        consumerID: UUID,
        owner: String?,
        state: RouteConsumerRetainState,
        spec: WatchSpec,
        accessToken: String?,
        afterReuse: (() async -> Void)? = nil
    ) async {
        if state.isDuplicate {
            RealtimeLifecycleDebugLog.duplicateRetainIgnored(
                routeKey: routeKey,
                consumerID: consumerID,
                owner: owner,
                consumerCount: state.consumerCount,
                sessionGeneration: state.sessionGeneration
            )
            return
        }
        RealtimeLifecycleDebugLog.consumerRetain(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: owner,
            consumerCount: state.consumerCount,
            joined: isTopicPhysicallyJoined(topic: topic),
            sessionGeneration: state.sessionGeneration
        )
        let joinDecision = withLocked {
            claimRegistryJoinLocked(routeKey: routeKey, topic: topic, consumerID: consumerID)
        }
        switch joinDecision {
        case .abandoned:
            return
        case .reuseExistingTopic:
            if state.consumerCount > 1 {
                RealtimeLifecycleDebugLog.routeReuse(routeKey: routeKey, topic: topic)
            }
            if let afterReuse {
                await afterReuse()
            }
        case .claimFirstJoin:
            RealtimeLifecycleDebugLog.routeJoin(routeKey: routeKey, topic: topic)
            #if DEBUG
            withLocked { testingRegistryJoinCount &+= 1 }
            #endif
            await joinChannel(spec, accessToken: accessToken)
        }
    }

    private struct RouteConsumerReleaseOutcome {
        var spec: WatchSpec?
        var shouldLeave: Bool
        var remaining: Int
        var duplicate: Bool
        var streamDetachOnly: Bool
        var streamsRemaining: Int = 0
    }

    private func finalizeConsumerRelease(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        outcome: RouteConsumerReleaseOutcome
    ) async {
        if outcome.duplicate {
            RealtimeLifecycleDebugLog.duplicateReleaseIgnored(
                routeKey: routeKey,
                consumerID: consumerID,
                owner: owner,
                consumerCount: outcome.remaining
            )
            return
        }
        if outcome.streamDetachOnly {
            RealtimeLifecycleDebugLog.consumerStreamDetach(
                routeKey: routeKey,
                consumerID: consumerID,
                owner: owner,
                consumerCount: outcome.remaining,
                streamsRemaining: outcome.streamsRemaining
            )
            return
        }
        RealtimeLifecycleDebugLog.consumerRelease(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: owner,
            consumerCount: outcome.remaining,
            joined: outcome.spec.map { isTopicPhysicallyJoined(topic: $0.topic) } ?? false,
            willLeave: outcome.shouldLeave
        )
        if outcome.shouldLeave, let spec = outcome.spec {
            let mayLeave = withLocked {
                claimRegistryLeaveLocked(routeKey: routeKey, topic: spec.topic)
            }
            guard mayLeave else { return }
            if spec.presenceKey != nil {
                await untrackRoomPresence(topic: spec.topic)
            }
            RealtimeLifecycleDebugLog.routeLeave(routeKey: routeKey, topic: spec.topic)
            #if DEBUG
            withLocked { testingRegistryLeaveCount &+= 1 }
            #endif
            await leaveChannel(topic: spec.topic, routeKey: routeKey)
        }
    }

    private func forceFinishAllConsumersLocked(reason: String) {
        for consumers in messageConsumersByRoute.values {
            for entry in consumers.values {
                entry.continuation?.finish()
                entry.presenceContinuation?.finish()
            }
        }
        for consumers in commentLikeConsumersByRoute.values {
            for entry in consumers.values {
                entry.continuation.finish()
            }
        }
        for consumers in contentLikeConsumersByRoute.values {
            for entry in consumers.values {
                entry.continuation.finish()
            }
        }
        for consumers in socialEntityConsumersByRoute.values {
            for entry in consumers.values {
                entry.continuation.finish()
            }
        }
        for consumers in commentPinConsumersByRoute.values {
            for entry in consumers.values {
                entry.continuation.finish()
            }
        }
        messageConsumersByRoute.removeAll()
        commentLikeConsumersByRoute.removeAll()
        contentLikeConsumersByRoute.removeAll()
        socialEntityConsumersByRoute.removeAll()
        commentPinConsumersByRoute.removeAll()
        routeEpochByKey.removeAll()
        releasedConsumerIDs.removeAll()
        _ = reason
    }

    private func messageContinuationsSnapshot(
        generation: UInt64
    ) -> [String: [AsyncStream<MessageRealtimeSignal>.Continuation]] {
        withLocked {
            var out: [String: [AsyncStream<MessageRealtimeSignal>.Continuation]] = [:]
            for (routeKey, consumers) in messageConsumersByRoute {
                let live = consumers.values
                    .filter { $0.sessionGeneration == generation }
                    .compactMap(\.continuation)
                if !live.isEmpty {
                    out[routeKey] = live
                }
            }
            return out
        }
    }

    private func commentLikeContinuationsSnapshot(
        generation: UInt64
    ) -> [String: [AsyncStream<CommentLikeRealtimeSignal>.Continuation]] {
        withLocked {
            var out: [String: [AsyncStream<CommentLikeRealtimeSignal>.Continuation]] = [:]
            for (routeKey, consumers) in commentLikeConsumersByRoute {
                let live = consumers.values
                    .filter { $0.sessionGeneration == generation }
                    .map(\.continuation)
                if !live.isEmpty {
                    out[routeKey] = live
                }
            }
            return out
        }
    }

    private func contentLikeContinuationsSnapshot(
        generation: UInt64
    ) -> [String: [AsyncStream<ContentLikeRealtimeSignal>.Continuation]] {
        withLocked {
            var out: [String: [AsyncStream<ContentLikeRealtimeSignal>.Continuation]] = [:]
            for (routeKey, consumers) in contentLikeConsumersByRoute {
                let live = consumers.values
                    .filter { $0.sessionGeneration == generation }
                    .map(\.continuation)
                if !live.isEmpty {
                    out[routeKey] = live
                }
            }
            return out
        }
    }

    private func socialEntityContinuationsSnapshot(
        generation: UInt64
    ) -> [String: [AsyncStream<SocialEntityRealtimeEvent>.Continuation]] {
        withLocked {
            var out: [String: [AsyncStream<SocialEntityRealtimeEvent>.Continuation]] = [:]
            for (routeKey, consumers) in socialEntityConsumersByRoute {
                let live = consumers.values
                    .filter { $0.sessionGeneration == generation }
                    .map(\.continuation)
                if !live.isEmpty {
                    out[routeKey] = live
                }
            }
            return out
        }
    }

    private func commentPinContinuationsSnapshot(
        generation: UInt64
    ) -> [String: [AsyncStream<CommentPinRealtimeSignal>.Continuation]] {
        withLocked {
            var out: [String: [AsyncStream<CommentPinRealtimeSignal>.Continuation]] = [:]
            for (routeKey, consumers) in commentPinConsumersByRoute {
                let live = consumers.values
                    .filter { $0.sessionGeneration == generation }
                    .map(\.continuation)
                if !live.isEmpty {
                    out[routeKey] = live
                }
            }
            return out
        }
    }

    /// Release one consumer. Leaves the physical channel only when the final consumer on the route is gone.
    func releaseWatch(_ consumer: RealtimeRouteConsumerHandle?) async {
        guard let consumer else { return }
        let alreadyReleased = withLocked { releasedConsumerIDs.contains(consumer.id) }
        if alreadyReleased {
            RealtimeLifecycleDebugLog.duplicateReleaseIgnored(
                routeKey: consumer.routeKey,
                consumerID: consumer.id,
                owner: consumer.debugOwner,
                consumerCount: logicalConsumerCount(routeKey: consumer.routeKey)
            )
            return
        }
        if consumer.routeKey.hasPrefix("comment-likes:") {
            await releaseCommentLikeConsumer(consumer)
        } else if consumer.routeKey.hasPrefix("content-likes:") {
            await releaseContentLikeConsumer(consumer)
        } else if consumer.routeKey.hasPrefix("social-entity:") {
            await releaseSocialEntityConsumer(consumer)
        } else if consumer.routeKey.hasPrefix("comment-pin:") {
            await releaseCommentPinConsumer(consumer)
        } else {
            await releaseMessageRouteConsumer(consumer)
        }
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
        RealtimeLifecycleDebugLog.connect()
    }

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let routesBeforeDisconnect = routeLifecycleSnapshot().activeRoutes
        withLocked {
        intentionalDisconnect = true
        watchSessionGeneration &+= 1
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        _isConnected = false
        receiveLoopRunning = false
        forceFinishAllConsumersLocked(reason: "disconnect")
        joinedTopics.removeAll()
        specsByRouteKey.removeAll()
        accessTokensByRouteKey.removeAll()
        presenceTrackConfigByRouteKey.removeAll()
        presenceTrackedByRouteKey.removeAll()
        presenceStateByTopic.removeAll()
        commentLikeSpecsByRouteKey.removeAll()
        contentLikeSpecsByRouteKey.removeAll()
        socialEntitySpecsByRouteKey.removeAll()
        }
        RealtimeLifecycleDebugLog.forceSessionClear(
            reason: "disconnect",
            sessionGeneration: withLocked { watchSessionGeneration }
        )
        RealtimeLifecycleDebugLog.disconnect(activeRoutes: routesBeforeDisconnect)
    }

    /// Foreground / network recovery — reconnect and rejoin active watches without
    /// finishing product streams (avoids duplicate subscriptions at the domain layer).
    func resumeAfterForeground() async {
        let (connected, hasSpecs) = withLocked {
            (_isConnected, !specsByRouteKey.isEmpty)
        }
        let snapshot = routeLifecycleSnapshot()
        RealtimeLifecycleDebugLog.foregroundResume(
            connected: connected,
            activeRoutes: snapshot.activeRoutes
        )
        if connected { return }
        if hasSpecs {
            await reconnectAndRejoin()
        } else {
            try? await connect()
        }
    }

    private func registerRoomLiveMessageConsumer(
        routeKey: String,
        consumerID: UUID,
        handle: RealtimeRouteConsumerHandle,
        continuation: AsyncStream<MessageRealtimeSignal>.Continuation,
        spec: WatchSpec,
        accessToken: String?,
        presenceTrack: RoomPresenceTrackConfig?,
        debugOwner: String?
    ) async {
        do {
            try await ensureConnected()
        } catch {
            continuation.finish()
            return
        }
        let startState = withLocked { () -> RouteConsumerRetainState in
            let generation = watchSessionGeneration
            var bucket = messageConsumersByRoute[routeKey, default: [:]]
            if bucket[consumerID] != nil {
                return RouteConsumerRetainState(
                    isDuplicate: true,
                    consumerCount: bucket.count,
                    sessionGeneration: generation
                )
            }
            let openStreams = presenceTrack != nil ? 2 : 1
            let routeEpoch = routeEpochByKey[routeKey, default: 0]
            bucket[consumerID] = MessageRouteConsumer(
                sessionGeneration: generation,
                routeEpoch: routeEpoch,
                continuation: continuation,
                presenceContinuation: nil,
                debugOwner: debugOwner,
                openStreamsRemaining: openStreams
            )
            messageConsumersByRoute[routeKey] = bucket
            specsByRouteKey[routeKey] = spec
            accessTokensByRouteKey[routeKey] = accessToken
            if let presenceTrack {
                presenceTrackConfigByRouteKey[routeKey] = presenceTrack
            } else {
                presenceTrackConfigByRouteKey.removeValue(forKey: routeKey)
            }
            let consumers = logicalConsumerCountLocked(routeKey: routeKey)
            return RouteConsumerRetainState(
                isDuplicate: false,
                consumerCount: consumers,
                sessionGeneration: generation
            )
        }
        if presenceTrack != nil, startState.consumerCount > 1 {
            await applyRegistryRetainAndJoin(
                routeKey: routeKey,
                topic: spec.topic,
                consumerID: consumerID,
                owner: debugOwner,
                state: startState,
                spec: spec,
                accessToken: accessToken,
                afterReuse: { await self.trackRoomPresenceIfNeeded(routeKey: routeKey, topic: spec.topic) }
            )
        } else {
            await applyRegistryRetainAndJoin(
                routeKey: routeKey,
                topic: spec.topic,
                consumerID: consumerID,
                owner: debugOwner,
                state: startState,
                spec: spec,
                accessToken: accessToken,
                afterReuse: nil
            )
        }
        if !startState.isDuplicate {
            continuation.onTermination = { @Sendable _ in
                Task { await self.releaseWatch(handle) }
            }
        }
    }

    /// Web Community `room-live-${id}` topic — messages + reactions (no presence track).
    func watchRoomMessages(roomID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        let streams = watchRoomLive(roomID: roomID, accessToken: accessToken, presenceTrack: nil)
        return streams.messages
    }

    /// Web `subscribeCommunityRoomLiveChannel` — messages, reactions, and optional presence.
    func watchRoomLive(
        roomID: String,
        accessToken: String?,
        presenceTrack: RoomPresenceTrackConfig?,
        debugOwner: String? = nil
    ) -> RoomLiveWatchStreams {
        let routeKey = "room:\(roomID)"
        let consumerID = UUID()
        let handle = RealtimeRouteConsumerHandle(
            id: consumerID,
            routeKey: routeKey,
            debugOwner: debugOwner
        )
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
                await self.registerRoomLiveMessageConsumer(
                    routeKey: routeKey,
                    consumerID: consumerID,
                    handle: handle,
                    continuation: continuation,
                    spec: spec,
                    accessToken: accessToken,
                    presenceTrack: presenceTrack,
                    debugOwner: debugOwner
                )
            }
        }

        let presence = AsyncStream<[RoomPresenceWireUser]> { continuation in
            Task {
                try? await self.ensureConnected()
                let joinState = self.withLocked { () -> (attached: Bool, snapshot: [String: [[String: Any]]]?) in
                    guard var existing = self.messageConsumersByRoute[routeKey]?[consumerID] else {
                        return (false, self.presenceStateByTopic[spec.topic])
                    }
                    existing.presenceContinuation = continuation
                    self.messageConsumersByRoute[routeKey]?[consumerID] = existing
                    self.specsByRouteKey[routeKey] = spec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    if let presenceTrack {
                        self.presenceTrackConfigByRouteKey[routeKey] = presenceTrack
                    }
                    let snapshot = self.presenceStateByTopic[spec.topic]
                    return (true, snapshot)
                }
                let snapshot = joinState.snapshot
                if joinState.attached, presenceTrack != nil {
                    await self.trackRoomPresenceIfNeeded(routeKey: routeKey, topic: spec.topic)
                }
                if let snapshot {
                    continuation.yield(RoomPresenceSemantics.dedupeByUserID(snapshot))
                }
                continuation.onTermination = { @Sendable _ in
                    Task { await self.releaseWatch(handle) }
                }
            }
        }

        return RoomLiveWatchStreams(messages: messages, presence: presence, consumer: handle)
    }

    /// Web DM thread `messages` filter `conversation_id=eq.${id}`.
    func watchConversationMessages(
        conversationID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
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
                    PostgresChangeBinding(
                        table: "message_reactions",
                        filter: "conversation_id=eq.\(conversationID)",
                        routeColumn: "conversation_id",
                        emitsReactionEvents: true
                    ),
                ]
            ),
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox read-cursor sync — `conversation_member_preferences` for the signed-in user.
    /// `MessageRealtimeSignal.conversationID` carries the affected conversation.
    func watchConversationReadCursors(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox — `room_messages` for the viewer's member rooms (unread bump when not open).
    func watchMemberRoomMessages(
        roomIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        let sorted = Array(Set(roomIDs)).sorted()
        let filter: String
        if sorted.isEmpty {
            return RealtimeMessageWatch(
                events: AsyncStream { $0.finish() },
                consumer: RealtimeRouteConsumerHandle(routeKey: "member-rooms", debugOwner: debugOwner)
            )
        }
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Member room cards — `room_members` insert/update/delete for visible rooms.
    func watchMemberRoomMembership(
        roomIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        let sorted = Array(Set(roomIDs)).sorted()
        guard !sorted.isEmpty else {
            return RealtimeMessageWatch(
                events: AsyncStream { $0.finish() },
                consumer: RealtimeRouteConsumerHandle(routeKey: "member-room-membership", debugOwner: debugOwner)
            )
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox — `messages` for loaded DM conversations (preview + reorder when not in thread).
    func watchInboxConversationMessages(
        conversationIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        let sorted = Array(Set(conversationIDs)).sorted()
        guard !sorted.isEmpty else {
            return RealtimeMessageWatch(
                events: AsyncStream { $0.finish() },
                consumer: RealtimeRouteConsumerHandle(routeKey: "inbox-dms", debugOwner: debugOwner)
            )
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Inbox read-cursor sync — `room_members` for the signed-in user.
    func watchRoomReadCursors(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Legacy Feed posts watch — Phase 10D uses ``watchSocialEntityChanges`` via ``SocialEntityRealtimeSession``.
    func watchFeedPosts(accessToken: String?, debugOwner: String? = nil) -> RealtimeMessageWatch {
        RealtimeMessageWatch(
            events: AsyncStream { $0.finish() },
            consumer: RealtimeRouteConsumerHandle(routeKey: "feed-posts-deprecated", debugOwner: debugOwner)
        )
    }

    /// Phase 10D — bounded entity postgres_changes for one table + filter.
    func watchSocialEntityChanges(
        table: SocialEntityRealtimeTable,
        filter: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeSocialEntityWatch {
        guard !filter.contains("__invalid_empty__") else {
            return RealtimeSocialEntityWatch(
                events: AsyncStream { $0.finish() },
                consumer: RealtimeRouteConsumerHandle(routeKey: "social-entity:empty", debugOwner: debugOwner)
            )
        }

        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: table, key: filter))"
        let topic = "realtime:\(routeKey)"
        let consumerID = UUID()
        let handle = RealtimeRouteConsumerHandle(
            id: consumerID,
            routeKey: routeKey,
            debugOwner: debugOwner
        )

        let events = AsyncStream { continuation in
            Task {
                try? await self.ensureConnected()
                let spec = SocialEntityWatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    filter: filter,
                    table: table
                )
                let joinSpec = WatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    bindings: [
                        PostgresChangeBinding(
                            table: table.rawValue,
                            filter: filter,
                            routeColumn: table.idColumn,
                            emitsReactionEvents: false,
                            emitsSocialEntityEvents: true
                        ),
                    ]
                )
                let startState = self.withLocked { () -> RouteConsumerRetainState in
                    let generation = self.watchSessionGeneration
                    var bucket = self.socialEntityConsumersByRoute[routeKey, default: [:]]
                    if bucket[consumerID] != nil {
                        return RouteConsumerRetainState(
                            isDuplicate: true,
                            consumerCount: bucket.count,
                            sessionGeneration: generation
                        )
                    }
                    let routeEpoch = self.routeEpochByKey[routeKey, default: 0]
                    bucket[consumerID] = SocialEntityRouteConsumer(
                        sessionGeneration: generation,
                        routeEpoch: routeEpoch,
                        continuation: continuation
                    )
                    self.socialEntityConsumersByRoute[routeKey] = bucket
                    self.socialEntitySpecsByRouteKey[routeKey] = spec
                    self.specsByRouteKey[routeKey] = joinSpec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    let consumers = self.logicalConsumerCountLocked(routeKey: routeKey)
                    return RouteConsumerRetainState(
                        isDuplicate: false,
                        consumerCount: consumers,
                        sessionGeneration: generation
                    )
                }
                await self.applyRegistryRetainAndJoin(
                    routeKey: routeKey,
                    topic: topic,
                    consumerID: consumerID,
                    owner: debugOwner,
                    state: startState,
                    spec: joinSpec,
                    accessToken: accessToken
                )
                if !startState.isDuplicate {
                    continuation.onTermination = { @Sendable _ in
                        Task { await self.releaseWatch(handle) }
                    }
                }
            }
        }
        return RealtimeSocialEntityWatch(events: events, consumer: handle)
    }

    /// Viewer outgoing follows — `followers.follower_id = viewer` (cross-device + echo).
    func watchRelationshipOutgoingFollows(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        watch(
            WatchSpec(
                topic: "realtime:relationship-outgoing-\(userID)",
                routeKey: "relationship:outgoing:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "followers",
                        filter: "follower_id=eq.\(userID)",
                        routeColumn: "follower_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Someone follows/unfollows the viewer — `followers.following_id = viewer`.
    func watchRelationshipIncomingFollows(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        watch(
            WatchSpec(
                topic: "realtime:relationship-incoming-\(userID)",
                routeKey: "relationship:incoming:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "followers",
                        filter: "following_id=eq.\(userID)",
                        routeColumn: "following_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Outgoing pending follow requests — `follow_requests.requester_id = viewer`.
    func watchRelationshipOutgoingFollowRequests(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        watch(
            WatchSpec(
                topic: "realtime:relationship-requests-out-\(userID)",
                routeKey: "relationship:requests-out:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "follow_requests",
                        filter: "requester_id=eq.\(userID)",
                        routeColumn: "requester_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Incoming follow requests — `follow_requests.target_id = viewer`.
    func watchRelationshipIncomingFollowRequests(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        watch(
            WatchSpec(
                topic: "realtime:relationship-requests-in-\(userID)",
                routeKey: "relationship:requests-in:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "follow_requests",
                        filter: "target_id=eq.\(userID)",
                        routeColumn: "target_id",
                        emitsReactionEvents: false
                    ),
                ]
            ),
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Activity inbox — idle until `notifications` postgres_changes for the viewer.
    func watchNotifications(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Viewer profile row — cross-device onboarding completion.
    func watchViewerProfile(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Daily psychology check-in — postgres_changes for the signed-in user.
    func watchTraderDailyCheckIns(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
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
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Phase 6D — analytical revision signal (`user_analytics_state` UPDATE for viewer).
    func watchUserAnalyticsRevision(
        userID: String,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        watch(
            WatchSpec(
                topic: "realtime:analytics-revision-\(userID)",
                routeKey: "analytics-revision:\(userID)",
                bindings: [
                    PostgresChangeBinding(
                        table: "user_analytics_state",
                        filter: "user_id=eq.\(userID)",
                        routeColumn: "user_id",
                        emitsReactionEvents: false,
                        postgresEvent: "UPDATE"
                    ),
                ]
            ),
            accessToken: accessToken,
            debugOwner: debugOwner
        )
    }

    /// Web `useCommentLikes` — `comment_likes` postgres_changes for visible comment ids.
    func watchCommentLikes(
        source: CommentLikeSource,
        commentIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeCommentLikeWatch {
        let unique = Array(Set(commentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        guard !unique.isEmpty else {
            return RealtimeCommentLikeWatch(
                events: AsyncStream { $0.finish() },
                consumer: RealtimeRouteConsumerHandle(routeKey: "comment-likes:empty", debugOwner: debugOwner)
            )
        }

        let filter = CommentLikeSemantics.realtimeFilter(source: source, commentIDs: unique)
        let routeKey = "comment-likes:\(CommentLikeSemantics.stableRouteSuffix(source: source, commentIDs: unique))"
        let topic = "realtime:\(routeKey)"
        let consumerID = UUID()
        let handle = RealtimeRouteConsumerHandle(
            id: consumerID,
            routeKey: routeKey,
            debugOwner: debugOwner
        )

        let events = AsyncStream { continuation in
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
                let startState = self.withLocked { () -> RouteConsumerRetainState in
                    let generation = self.watchSessionGeneration
                    var bucket = self.commentLikeConsumersByRoute[routeKey, default: [:]]
                    if bucket[consumerID] != nil {
                        return RouteConsumerRetainState(
                            isDuplicate: true,
                            consumerCount: bucket.count,
                            sessionGeneration: generation
                        )
                    }
                    let routeEpoch = self.routeEpochByKey[routeKey, default: 0]
                    bucket[consumerID] = CommentLikeRouteConsumer(
                        sessionGeneration: generation,
                        routeEpoch: routeEpoch,
                        continuation: continuation
                    )
                    self.commentLikeConsumersByRoute[routeKey] = bucket
                    self.commentLikeSpecsByRouteKey[routeKey] = spec
                    self.specsByRouteKey[routeKey] = joinSpec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    let consumers = self.logicalConsumerCountLocked(routeKey: routeKey)
                    return RouteConsumerRetainState(
                        isDuplicate: false,
                        consumerCount: consumers,
                        sessionGeneration: generation
                    )
                }
                await self.applyRegistryRetainAndJoin(
                    routeKey: routeKey,
                    topic: topic,
                    consumerID: consumerID,
                    owner: debugOwner,
                    state: startState,
                    spec: joinSpec,
                    accessToken: accessToken
                )
                if !startState.isDuplicate {
                    continuation.onTermination = { @Sendable _ in
                        Task { await self.releaseWatch(handle) }
                    }
                }
            }
        }
        return RealtimeCommentLikeWatch(events: events, consumer: handle)
    }

    /// Phase 10C — bounded content-like postgres_changes (`reel_likes`, `trade_likes`, …).
    func watchContentLikes(
        table: ContentLikeTable,
        contentIDs: [String],
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeContentLikeWatch {
        let unique = Array(Set(contentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        guard !unique.isEmpty, unique.count <= ContentLikeSemantics.realtimeInFilterMaxIDs else {
            return RealtimeContentLikeWatch(
                events: AsyncStream { $0.finish() },
                consumer: RealtimeRouteConsumerHandle(routeKey: "content-likes:empty", debugOwner: debugOwner)
            )
        }

        let filter = ContentLikeSemantics.realtimeFilter(table: table, contentIDs: unique)
        let routeKey = "content-likes:\(ContentLikeSemantics.stableRouteSuffix(table: table, contentIDs: unique))"
        let topic = "realtime:\(routeKey)"
        let consumerID = UUID()
        let handle = RealtimeRouteConsumerHandle(
            id: consumerID,
            routeKey: routeKey,
            debugOwner: debugOwner
        )

        let events = AsyncStream { continuation in
            Task {
                try? await self.ensureConnected()
                let spec = ContentLikeWatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    filter: filter,
                    table: table,
                    visibleContentIDs: Set(unique)
                )
                let joinSpec = WatchSpec(
                    topic: topic,
                    routeKey: routeKey,
                    bindings: [
                        PostgresChangeBinding(
                            table: table.rawValue,
                            filter: filter,
                            routeColumn: table.foreignKeyColumn,
                            emitsReactionEvents: false,
                            emitsContentLikeEvents: true
                        ),
                    ]
                )
                let startState = self.withLocked { () -> RouteConsumerRetainState in
                    let generation = self.watchSessionGeneration
                    var bucket = self.contentLikeConsumersByRoute[routeKey, default: [:]]
                    if bucket[consumerID] != nil {
                        return RouteConsumerRetainState(
                            isDuplicate: true,
                            consumerCount: bucket.count,
                            sessionGeneration: generation
                        )
                    }
                    let routeEpoch = self.routeEpochByKey[routeKey, default: 0]
                    bucket[consumerID] = ContentLikeRouteConsumer(
                        sessionGeneration: generation,
                        routeEpoch: routeEpoch,
                        continuation: continuation
                    )
                    self.contentLikeConsumersByRoute[routeKey] = bucket
                    self.contentLikeSpecsByRouteKey[routeKey] = spec
                    self.specsByRouteKey[routeKey] = joinSpec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    let consumers = self.logicalConsumerCountLocked(routeKey: routeKey)
                    return RouteConsumerRetainState(
                        isDuplicate: false,
                        consumerCount: consumers,
                        sessionGeneration: generation
                    )
                }
                await self.applyRegistryRetainAndJoin(
                    routeKey: routeKey,
                    topic: topic,
                    consumerID: consumerID,
                    owner: debugOwner,
                    state: startState,
                    spec: joinSpec,
                    accessToken: accessToken
                )
                if !startState.isDuplicate {
                    continuation.onTermination = { @Sendable _ in
                        Task { await self.releaseWatch(handle) }
                    }
                }
            }
        }
        return RealtimeContentLikeWatch(events: events, consumer: handle)
    }

    /// Web TradeSocialLayer — `UPDATE` on comment rows for `pinned` flips.
    func watchCommentPinUpdates(
        target: InteractionTarget,
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeCommentPinWatch {
        let table = Self.commentTable(for: target.kind)
        let foreignKey = Self.commentForeignKey(for: target.kind)
        let filter = "\(foreignKey)=eq.\(target.id)"
        let routeKey = "comment-pin:\(target.kind.rawValue):\(target.id)"
        let topic = "realtime:\(routeKey)"

        let consumerID = UUID()
        let handle = RealtimeRouteConsumerHandle(
            id: consumerID,
            routeKey: routeKey,
            debugOwner: debugOwner
        )
        let events = AsyncStream<CommentPinRealtimeSignal>(bufferingPolicy: .unbounded) { continuation in
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
                let startState = self.withLocked { () -> RouteConsumerRetainState in
                    let generation = self.watchSessionGeneration
                    var bucket = self.commentPinConsumersByRoute[routeKey, default: [:]]
                    if bucket[consumerID] != nil {
                        return RouteConsumerRetainState(
                            isDuplicate: true,
                            consumerCount: bucket.count,
                            sessionGeneration: generation
                        )
                    }
                    let routeEpoch = self.routeEpochByKey[routeKey, default: 0]
                    bucket[consumerID] = CommentPinRouteConsumer(
                        sessionGeneration: generation,
                        routeEpoch: routeEpoch,
                        continuation: continuation
                    )
                    self.commentPinConsumersByRoute[routeKey] = bucket
                    self.specsByRouteKey[routeKey] = joinSpec
                    self.accessTokensByRouteKey[routeKey] = accessToken
                    let consumers = self.logicalConsumerCountLocked(routeKey: routeKey)
                    return RouteConsumerRetainState(
                        isDuplicate: false,
                        consumerCount: consumers,
                        sessionGeneration: generation
                    )
                }
                await self.applyRegistryRetainAndJoin(
                    routeKey: routeKey,
                    topic: topic,
                    consumerID: consumerID,
                    owner: debugOwner,
                    state: startState,
                    spec: joinSpec,
                    accessToken: accessToken
                )
                if !startState.isDuplicate {
                    continuation.onTermination = { @Sendable _ in
                        Task { await self.releaseWatch(handle) }
                    }
                }
            }
        }
        return RealtimeCommentPinWatch(events: events, consumer: handle)
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
        accessToken: String?,
        debugOwner: String? = nil
    ) -> RealtimeMessageWatch {
        let consumerID = UUID()
        let handle = RealtimeRouteConsumerHandle(
            id: consumerID,
            routeKey: spec.routeKey,
            debugOwner: debugOwner
        )
        let events = AsyncStream<MessageRealtimeSignal> { continuation in
            Task {
                try? await self.ensureConnected()
                let startState = self.withLocked { () -> RouteConsumerRetainState in
                    let generation = self.watchSessionGeneration
                    var bucket = self.messageConsumersByRoute[spec.routeKey, default: [:]]
                    if bucket[consumerID] != nil {
                        return RouteConsumerRetainState(
                            isDuplicate: true,
                            consumerCount: bucket.count,
                            sessionGeneration: generation
                        )
                    }
                    let routeEpoch = self.routeEpochByKey[spec.routeKey, default: 0]
                    bucket[consumerID] = MessageRouteConsumer(
                        sessionGeneration: generation,
                        routeEpoch: routeEpoch,
                        continuation: continuation,
                        presenceContinuation: nil,
                        debugOwner: debugOwner,
                        openStreamsRemaining: 1
                    )
                    self.messageConsumersByRoute[spec.routeKey] = bucket
                    self.specsByRouteKey[spec.routeKey] = spec
                    self.accessTokensByRouteKey[spec.routeKey] = accessToken
                    let consumers = self.logicalConsumerCountLocked(routeKey: spec.routeKey)
                    return RouteConsumerRetainState(
                        isDuplicate: false,
                        consumerCount: consumers,
                        sessionGeneration: generation
                    )
                }
                await self.applyRegistryRetainAndJoin(
                    routeKey: spec.routeKey,
                    topic: spec.topic,
                    consumerID: consumerID,
                    owner: debugOwner,
                    state: startState,
                    spec: spec,
                    accessToken: accessToken
                )
                if !startState.isDuplicate {
                    continuation.onTermination = { @Sendable _ in
                        Task { await self.releaseWatch(handle) }
                    }
                }
            }
        }
        return RealtimeMessageWatch(events: events, consumer: handle)
    }

    private func releaseMessageRouteConsumer(_ consumer: RealtimeRouteConsumerHandle) async {
        let routeKey = consumer.routeKey
        let consumerID = consumer.id
        let outcome = withLocked { () -> RouteConsumerReleaseOutcome in
            guard var bundle = messageConsumersByRoute[routeKey]?[consumerID] else {
                return RouteConsumerReleaseOutcome(
                    spec: nil,
                    shouldLeave: false,
                    remaining: logicalConsumerCountLocked(routeKey: routeKey),
                    duplicate: true,
                    streamDetachOnly: false
                )
            }
            bundle.openStreamsRemaining -= 1
            if bundle.openStreamsRemaining > 0 {
                messageConsumersByRoute[routeKey]?[consumerID] = bundle
                return RouteConsumerReleaseOutcome(
                    spec: specsByRouteKey[routeKey],
                    shouldLeave: false,
                    remaining: logicalConsumerCountLocked(routeKey: routeKey),
                    duplicate: false,
                    streamDetachOnly: true,
                    streamsRemaining: bundle.openStreamsRemaining
                )
            }
            messageConsumersByRoute[routeKey]?.removeValue(forKey: consumerID)
            if messageConsumersByRoute[routeKey]?.isEmpty == true {
                messageConsumersByRoute.removeValue(forKey: routeKey)
            }
            noteConsumerFullyReleasedLocked(consumerID: consumerID)
            let remaining = logicalConsumerCountLocked(routeKey: routeKey)
            guard remaining == 0 else {
                return RouteConsumerReleaseOutcome(
                    spec: specsByRouteKey[routeKey],
                    shouldLeave: false,
                    remaining: remaining,
                    duplicate: false,
                    streamDetachOnly: false
                )
            }
            let spec = specsByRouteKey.removeValue(forKey: routeKey)
            accessTokensByRouteKey.removeValue(forKey: routeKey)
            presenceTrackConfigByRouteKey.removeValue(forKey: routeKey)
            presenceTrackedByRouteKey.removeValue(forKey: routeKey)
            if let topic = spec?.topic {
                presenceStateByTopic.removeValue(forKey: topic)
            }
            return RouteConsumerReleaseOutcome(
                spec: spec,
                shouldLeave: true,
                remaining: 0,
                duplicate: false,
                streamDetachOnly: false
            )
        }
        await finalizeConsumerRelease(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: consumer.debugOwner,
            outcome: outcome
        )
    }

    private func releaseSingleStreamRouteConsumer(
        routeKey: String,
        consumerID: UUID,
        owner: String?,
        isRegistered: () -> Bool,
        removeConsumer: () -> Void,
        removeRouteSpecsWhenEmpty: () -> WatchSpec?
    ) async {
        let outcome = withLocked { () -> RouteConsumerReleaseOutcome in
            guard isRegistered() else {
                return RouteConsumerReleaseOutcome(
                    spec: nil,
                    shouldLeave: false,
                    remaining: logicalConsumerCountLocked(routeKey: routeKey),
                    duplicate: true,
                    streamDetachOnly: false
                )
            }
            removeConsumer()
            noteConsumerFullyReleasedLocked(consumerID: consumerID)
            let remaining = logicalConsumerCountLocked(routeKey: routeKey)
            guard remaining == 0 else {
                return RouteConsumerReleaseOutcome(
                    spec: specsByRouteKey[routeKey],
                    shouldLeave: false,
                    remaining: remaining,
                    duplicate: false,
                    streamDetachOnly: false
                )
            }
            let spec = removeRouteSpecsWhenEmpty()
            return RouteConsumerReleaseOutcome(
                spec: spec,
                shouldLeave: true,
                remaining: 0,
                duplicate: false,
                streamDetachOnly: false
            )
        }
        await finalizeConsumerRelease(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: owner,
            outcome: outcome
        )
    }

    private func releaseCommentLikeConsumer(_ consumer: RealtimeRouteConsumerHandle) async {
        let routeKey = consumer.routeKey
        let consumerID = consumer.id
        await releaseSingleStreamRouteConsumer(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: consumer.debugOwner,
            isRegistered: { commentLikeConsumersByRoute[routeKey]?[consumerID] != nil },
            removeConsumer: {
                commentLikeConsumersByRoute[routeKey]?.removeValue(forKey: consumerID)
                if commentLikeConsumersByRoute[routeKey]?.isEmpty == true {
                    commentLikeConsumersByRoute.removeValue(forKey: routeKey)
                }
            },
            removeRouteSpecsWhenEmpty: {
                commentLikeSpecsByRouteKey.removeValue(forKey: routeKey)
                let spec = specsByRouteKey.removeValue(forKey: routeKey)
                accessTokensByRouteKey.removeValue(forKey: routeKey)
                return spec
            }
        )
    }

    private func releaseContentLikeConsumer(_ consumer: RealtimeRouteConsumerHandle) async {
        let routeKey = consumer.routeKey
        let consumerID = consumer.id
        await releaseSingleStreamRouteConsumer(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: consumer.debugOwner,
            isRegistered: { contentLikeConsumersByRoute[routeKey]?[consumerID] != nil },
            removeConsumer: {
                contentLikeConsumersByRoute[routeKey]?.removeValue(forKey: consumerID)
                if contentLikeConsumersByRoute[routeKey]?.isEmpty == true {
                    contentLikeConsumersByRoute.removeValue(forKey: routeKey)
                }
            },
            removeRouteSpecsWhenEmpty: {
                contentLikeSpecsByRouteKey.removeValue(forKey: routeKey)
                let spec = specsByRouteKey.removeValue(forKey: routeKey)
                accessTokensByRouteKey.removeValue(forKey: routeKey)
                return spec
            }
        )
    }

    private func releaseSocialEntityConsumer(_ consumer: RealtimeRouteConsumerHandle) async {
        let routeKey = consumer.routeKey
        let consumerID = consumer.id
        await releaseSingleStreamRouteConsumer(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: consumer.debugOwner,
            isRegistered: { socialEntityConsumersByRoute[routeKey]?[consumerID] != nil },
            removeConsumer: {
                socialEntityConsumersByRoute[routeKey]?.removeValue(forKey: consumerID)
                if socialEntityConsumersByRoute[routeKey]?.isEmpty == true {
                    socialEntityConsumersByRoute.removeValue(forKey: routeKey)
                }
            },
            removeRouteSpecsWhenEmpty: {
                socialEntitySpecsByRouteKey.removeValue(forKey: routeKey)
                let spec = specsByRouteKey.removeValue(forKey: routeKey)
                accessTokensByRouteKey.removeValue(forKey: routeKey)
                return spec
            }
        )
    }

    private func releaseCommentPinConsumer(_ consumer: RealtimeRouteConsumerHandle) async {
        let routeKey = consumer.routeKey
        let consumerID = consumer.id
        await releaseSingleStreamRouteConsumer(
            routeKey: routeKey,
            consumerID: consumerID,
            owner: consumer.debugOwner,
            isRegistered: { commentPinConsumersByRoute[routeKey]?[consumerID] != nil },
            removeConsumer: {
                commentPinConsumersByRoute[routeKey]?.removeValue(forKey: consumerID)
                if commentPinConsumersByRoute[routeKey]?.isEmpty == true {
                    commentPinConsumersByRoute.removeValue(forKey: routeKey)
                }
            },
            removeRouteSpecsWhenEmpty: {
                let spec = specsByRouteKey.removeValue(forKey: routeKey)
                accessTokensByRouteKey.removeValue(forKey: routeKey)
                return spec
            }
        )
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
                "event": binding.postgresEvent,
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
        let snapshot = routeLifecycleSnapshot(routeKey: spec.routeKey)
        RealtimeLifecycleDebugLog.join(
            topic: spec.topic,
            routeKey: spec.routeKey,
            activeRoutes: snapshot.activeRoutes,
            joinedTopics: snapshot.joinedTopics
        )
        #if DEBUG
        withLocked { testingTransportJoinCount &+= 1 }
        #endif
        await sendJSON([
            "topic": spec.topic,
            "event": "phx_join",
            "payload": payload,
            "ref": ref,
            "join_ref": ref,
        ])
    }

    private func leaveChannel(topic: String, routeKey: String? = nil) async {
        let snapshot = routeLifecycleSnapshot(routeKey: routeKey)
        RealtimeLifecycleDebugLog.leave(
            topic: topic,
            routeKey: routeKey,
            activeRoutes: snapshot.activeRoutes,
            joinedTopics: snapshot.joinedTopics
        )
        #if DEBUG
        withLocked { testingTransportLeaveCount &+= 1 }
        #endif
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
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            return !intentionalDisconnect && !specsByRouteKey.isEmpty
        }
        if shouldReconnect {
            let snapshot = routeLifecycleSnapshot()
            RealtimeLifecycleDebugLog.socketDropped(activeRoutes: snapshot.activeRoutes)
            Task {
                await SocialRealtimeReconciliationCoordinator.shared.noteDisconnectObserved(
                    activeRoutes: snapshot.activeRoutes
                )
            }
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

            RealtimeLifecycleDebugLog.reconnectBegin(
                activeRoutes: specs.count,
                attempt: attempt
            )

            do {
                try await connect()
                for spec in specs {
                    if Task.isCancelled { return }
                    let shouldRejoin = withLocked {
                        presenceTrackedByRouteKey[spec.routeKey] = false
                        presenceStateByTopic.removeValue(forKey: spec.topic)
                        return logicalConsumerCountLocked(routeKey: spec.routeKey) > 0
                    }
                    let snapshot = routeLifecycleSnapshot(routeKey: spec.routeKey)
                    RealtimeLifecycleDebugLog.rejoin(
                        routeKey: spec.routeKey,
                        topic: spec.topic,
                        skipped: !shouldRejoin,
                        activeRoutes: snapshot.activeRoutes,
                        joinedTopics: snapshot.joinedTopics
                    )
                    if shouldRejoin {
                        RealtimeLifecycleDebugLog.routeRejoin(routeKey: spec.routeKey, topic: spec.topic)
                        await joinChannel(spec, accessToken: tokens[spec.routeKey] ?? nil)
                    } else if spec.presenceKey != nil {
                        await trackRoomPresenceIfNeeded(routeKey: spec.routeKey, topic: spec.topic)
                    }
                }
                let endSnapshot = routeLifecycleSnapshot()
                RealtimeLifecycleDebugLog.reconnectEnd(
                    activeRoutes: endSnapshot.activeRoutes,
                    joinedTopics: endSnapshot.joinedTopics
                )
                for spec in specs where spec.routeKey.hasPrefix("analytics-revision:") {
                    let viewer = spec.routeKey.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                    if !viewer.isEmpty {
                        Task { @MainActor in
                            AnalyticsRevisionRealtimeSession.shared.notifyReconnectIfBound()
                        }
                    }
                }
                Task {
                    await SocialRealtimeReconciliationCoordinator.shared.noteReconnectCompleted(
                        activeRoutes: endSnapshot.activeRoutes
                    )
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
              let topic = object["topic"] as? String
        else { return }

        let routeKey = withLocked {
            specsByRouteKey.first(where: { $0.value.topic == topic })?.key
        }
        guard let routeKey else { return }

        if topic.hasPrefix("realtime:analytics-revision-") {
            let viewer = routeKey.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            if !viewer.isEmpty {
                AnalyticsReconciliationProbe.subscribed(viewer: viewer)
            }
            return
        }

        guard topic.hasPrefix("realtime:room-live-") else { return }
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
        let generation = withLocked { watchSessionGeneration }
        let snapshot = withLocked { () -> (
            [String: [[String: Any]]],
            [AsyncStream<[RoomPresenceWireUser]>.Continuation]
        ) in
            let state = presenceStateByTopic[topic] ?? [:]
            let routeKey = specsByRouteKey.first(where: { $0.value.topic == topic })?.key
            let presenceConts: [AsyncStream<[RoomPresenceWireUser]>.Continuation]
            if let routeKey {
                presenceConts = messageConsumersByRoute[routeKey]?.values
                    .filter { $0.sessionGeneration == generation }
                    .compactMap(\.presenceContinuation) ?? []
            } else {
                presenceConts = []
            }
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

        let generation = withLocked { watchSessionGeneration }
        let snapshot = withLocked {
            (
                Array(specsByRouteKey.values),
                commentLikeSpecsByRouteKey,
                contentLikeSpecsByRouteKey,
                socialEntitySpecsByRouteKey
            )
        }
        let specs = snapshot.0
        let likeSpecs = snapshot.1
        let contentLikeSpecs = snapshot.2
        let socialEntitySpecs = snapshot.3
        let allContinuations = messageContinuationsSnapshot(generation: generation)
        let allCommentLikeContinuations = commentLikeContinuationsSnapshot(generation: generation)
        let allContentLikeContinuations = contentLikeContinuationsSnapshot(generation: generation)
        let allSocialEntityContinuations = socialEntityContinuationsSnapshot(generation: generation)
        let allCommentPinContinuations = commentPinContinuationsSnapshot(generation: generation)

        if table == "user_analytics_state" {
            handleUserAnalyticsRevisionChanges(
                type: type,
                record: record,
                specs: specs,
                continuations: allContinuations
            )
            return
        }

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

        if let contentTable = ContentLikeTable(rawValue: table) {
            handleContentLikeChanges(
                table: contentTable,
                type: type,
                record: record,
                oldRecord: oldRecord,
                likeSpecs: contentLikeSpecs,
                continuations: allContentLikeContinuations
            )
            return
        }

        if let entityTable = SocialEntityRealtimeTable(rawValue: table) {
            handleSocialEntityChanges(
                table: entityTable,
                type: type,
                record: record,
                oldRecord: oldRecord,
                specs: socialEntitySpecs,
                continuations: allSocialEntityContinuations
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
            if binding.emitsCommentLikeEvents || binding.emitsContentLikeEvents || binding.emitsSocialEntityEvents
                || binding.emitsCommentPinEvents
            {
                continue
            }
            let scope = (record?[binding.routeColumn] as? String)
                ?? (oldRecord?[binding.routeColumn] as? String)
            let scopedMatch: Bool
            if spec.routeKey.hasPrefix("dm-read:")
                || spec.routeKey.hasPrefix("room-read:")
                || spec.routeKey.hasPrefix("notifications:")
                || spec.routeKey.hasPrefix("relationship:")
                || spec.routeKey == "member-rooms"
                || spec.routeKey == "inbox-dms"
                || spec.routeKey == "member-room-membership"
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
                    deletedForEveryone: Self.parseDeletedForEveryone(from: record),
                    recordPayload: (record ?? oldRecord).flatMap { PostgresChangeRecordCodec.encode($0) }
                )
            }
            for continuation in allContinuations[spec.routeKey] ?? [] {
                continuation.yield(signal)
            }
        }
    }

    private func handleUserAnalyticsRevisionChanges(
        type: String,
        record: [String: Any]?,
        specs: [WatchSpec],
        continuations: [String: [AsyncStream<MessageRealtimeSignal>.Continuation]]
    ) {
        guard type.uppercased() == "UPDATE", let record else { return }
        guard let userID = record["user_id"] as? String,
              let revision = Self.parseInt64Field(record["revision"]),
              revision > 0
        else { return }
        let updatedAt = record["updated_at"] as? String
        let signal = MessageRealtimeSignal(
            kind: .update,
            messageID: userID,
            conversationID: userID,
            analyticsRevision: revision,
            analyticsUpdatedAt: updatedAt
        )
        let routeKey = "analytics-revision:\(userID)"
        guard specs.contains(where: { $0.routeKey == routeKey }) else { return }
        for continuation in continuations[routeKey] ?? [] {
            continuation.yield(signal)
        }
    }

    private static func parseInt64Field(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        case let int as Int:
            return Int64(int)
        case let int64 as Int64:
            return int64
        default:
            return nil
        }
    }

    private func handleSocialEntityChanges(
        table: SocialEntityRealtimeTable,
        type: String,
        record: [String: Any]?,
        oldRecord: [String: Any]?,
        specs: [String: SocialEntityWatchSpec],
        continuations: [String: [AsyncStream<SocialEntityRealtimeEvent>.Continuation]]
    ) {
        let mutation: SocialEntityRealtimeMutation
        switch type.uppercased() {
        case "INSERT": mutation = .insert
        case "UPDATE": mutation = .update
        case "DELETE": mutation = .delete
        default: return
        }
        guard let event = SocialEntityRealtimeSemantics.parseEvent(
            table: table,
            mutation: mutation,
            record: record,
            oldRecord: oldRecord
        ) else { return }

        for (routeKey, spec) in specs where spec.table == table {
            for continuation in continuations[routeKey] ?? [] {
                continuation.yield(event)
            }
        }
    }

    private func handleContentLikeChanges(
        table: ContentLikeTable,
        type: String,
        record: [String: Any]?,
        oldRecord: [String: Any]?,
        likeSpecs: [String: ContentLikeWatchSpec],
        continuations: [String: [AsyncStream<ContentLikeRealtimeSignal>.Continuation]]
    ) {
        let row = record ?? oldRecord
        guard let row else { return }
        let column = table.foreignKeyColumn
        let contentID = (row[column] as? String) ?? ""
        let userID = (row["user_id"] as? String) ?? ""
        let rowID = (row["id"] as? String)
        guard !contentID.isEmpty, !userID.isEmpty else { return }

        let kind: ContentLikeSemantics.RealtimeMutationKind
        switch type.uppercased() {
        case "INSERT": kind = .insert
        case "DELETE": kind = .delete
        default: return
        }

        let signal = ContentLikeRealtimeSignal(
            table: table,
            contentID: contentID,
            userID: userID,
            kind: kind,
            rowID: rowID
        )

        for (routeKey, spec) in likeSpecs where spec.table == table {
            guard spec.visibleContentIDs.contains(contentID) else { continue }
            for continuation in continuations[routeKey] ?? [] {
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

#if DEBUG
extension LiveSupabaseRealtimeProvider {
    struct RouteLifecycleTestSnapshot: Sendable, Equatable {
        var consumerCount: Int
        var isJoined: Bool
        var activeRouteCount: Int
        var sessionGeneration: UInt64
    }

    func testing_routeSnapshot(routeKey: String) -> RouteLifecycleTestSnapshot {
        withLocked {
            let topic = specsByRouteKey[routeKey]?.topic
            let joined = topic.map { joinedTopics.contains($0) } ?? false
            return RouteLifecycleTestSnapshot(
                consumerCount: logicalConsumerCountLocked(routeKey: routeKey),
                isJoined: joined,
                activeRouteCount: specsByRouteKey.count,
                sessionGeneration: watchSessionGeneration
            )
        }
    }

    func testing_injectMessageSignal(routeKey: String, signal: MessageRealtimeSignal) {
        let generation = withLocked { watchSessionGeneration }
        let conts = messageContinuationsSnapshot(generation: generation)[routeKey] ?? []
        for continuation in conts {
            continuation.yield(signal)
        }
    }

    func testing_injectContentLikeSignal(routeKey: String, signal: ContentLikeRealtimeSignal) {
        let generation = withLocked { watchSessionGeneration }
        let conts = contentLikeContinuationsSnapshot(generation: generation)[routeKey] ?? []
        for continuation in conts {
            continuation.yield(signal)
        }
    }

    func testing_injectSocialEntitySignal(routeKey: String, signal: SocialEntityRealtimeEvent) {
        let generation = withLocked { watchSessionGeneration }
        let conts = socialEntityContinuationsSnapshot(generation: generation)[routeKey] ?? []
        for continuation in conts {
            continuation.yield(signal)
        }
    }

    func testing_sessionGeneration() -> UInt64 {
        withLocked { watchSessionGeneration }
    }

    func testing_waitForConsumerCount(routeKey: String, minimum: Int, timeoutMs: Int = 2_000) async -> Bool {
        let stepNs: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if testing_routeSnapshot(routeKey: routeKey).consumerCount >= minimum {
                return true
            }
            try? await Task.sleep(nanoseconds: stepNs)
        }
        return testing_routeSnapshot(routeKey: routeKey).consumerCount >= minimum
    }

    func testing_registryJoinCount() -> Int {
        withLocked { testingRegistryJoinCount }
    }

    func testing_registryLeaveCount() -> Int {
        withLocked { testingRegistryLeaveCount }
    }

    func testing_resetRegistryLifecycleCounters() {
        withLocked {
            testingRegistryJoinCount = 0
            testingRegistryLeaveCount = 0
            testingTransportJoinCount = 0
            testingTransportLeaveCount = 0
        }
    }

    func testing_transportJoinCount() -> Int {
        withLocked { testingTransportJoinCount }
    }

    func testing_transportLeaveCount() -> Int {
        withLocked { testingTransportLeaveCount }
    }

    /// Simulates stale async retain work attempting a second registry join after the route is already joined.
    func testing_simulateStaleRegistryJoinAttempt(_ handle: RealtimeRouteConsumerHandle) async {
        guard let spec = withLocked({ specsByRouteKey[handle.routeKey] }) else { return }
        let decision = withLocked {
            claimRegistryJoinLocked(
                routeKey: handle.routeKey,
                topic: spec.topic,
                consumerID: handle.id
            )
        }
        if decision == .claimFirstJoin {
            await joinChannel(spec, accessToken: withLocked { accessTokensByRouteKey[handle.routeKey] ?? nil })
        }
    }

    /// Simulates a second registry retain for the same consumer handle (duplicate AsyncStream registration).
    func testing_simulateDuplicateSocialEntityRetain(_ handle: RealtimeRouteConsumerHandle) async {
        let routeKey = handle.routeKey
        let topic = "realtime:\(routeKey)"
        let joinSpec = withLocked { specsByRouteKey[routeKey] }
        guard let joinSpec else { return }
        let state = withLocked { () -> RouteConsumerRetainState in
            let generation = watchSessionGeneration
            let bucket = socialEntityConsumersByRoute[routeKey] ?? [:]
            return RouteConsumerRetainState(
                isDuplicate: bucket[handle.id] != nil,
                consumerCount: bucket.count,
                sessionGeneration: generation
            )
        }
        await applyRegistryRetainAndJoin(
            routeKey: routeKey,
            topic: topic,
            consumerID: handle.id,
            owner: handle.debugOwner,
            state: state,
            spec: joinSpec,
            accessToken: withLocked { accessTokensByRouteKey[routeKey] ?? nil }
        )
    }
}
#endif

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
    /// Present when the event originated from `room_message_reactions` or `message_reactions`.
    var reactionEvent: ReactionEvent? = nil
    /// Phase 6D — `user_analytics_state.revision` on UPDATE (signal only, not authoritative metrics).
    var analyticsRevision: Int64? = nil
    var analyticsUpdatedAt: String? = nil
    /// Raw postgres `record` JSON when available (notifications, messages, followers, …).
    var recordPayload: Data? = nil
}

typealias RoomRealtimeSignal = MessageRealtimeSignal

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

    func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String? = nil
    ) async throws -> String {
        _ = (bucket, path, data, contentType, cacheControl)
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
