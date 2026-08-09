import Foundation

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
    private struct WatchSpec: Sendable {
        var topic: String
        var table: String
        var filter: String
        /// Key used to route inbound events (`room:{id}` / `dm:{id}`).
        var routeKey: String
        /// Column that identifies the route (`room_id` / `conversation_id`).
        var routeColumn: String
    }

    private let configuration: AppConfiguration
    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var _isConnected = false
    private let session: URLSession
    private var receiveLoopRunning = false
    private var heartbeatTask: Task<Void, Never>?
    private var refCounter = 0
    private var continuations: [String: [AsyncStream<MessageRealtimeSignal>.Continuation]] = [:]
    private var joinedTopics: Set<String> = []
    private var specsByRouteKey: [String: WatchSpec] = [:]

    init(configuration: AppConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.session = urlSession
    }

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isConnected
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
        lock.lock()
        webSocketTask = task
        _isConnected = true
        lock.unlock()
        startReceiveLoopIfNeeded()
        startHeartbeat()
    }

    func disconnect() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        lock.lock()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        _isConnected = false
        receiveLoopRunning = false
        for values in continuations.values {
            for continuation in values {
                continuation.finish()
            }
        }
        continuations.removeAll()
        joinedTopics.removeAll()
        specsByRouteKey.removeAll()
        lock.unlock()
    }

    /// Web Community `room-${id}` + `room_messages` filter.
    func watchRoomMessages(roomID: String, accessToken: String?) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:room-\(roomID)",
                table: "room_messages",
                filter: "room_id=eq.\(roomID)",
                routeKey: "room:\(roomID)",
                routeColumn: "room_id"
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingRoomMessages(roomID: String) async {
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
                table: "messages",
                filter: "conversation_id=eq.\(conversationID)",
                routeKey: "dm:\(conversationID)",
                routeColumn: "conversation_id"
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
                table: "conversation_member_preferences",
                filter: "user_id=eq.\(userID)",
                routeKey: "dm-read:\(userID)",
                routeColumn: "conversation_id"
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
                table: "room_messages",
                filter: filter,
                routeKey: "member-rooms",
                routeColumn: "room_id"
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingMemberRoomMessages() async {
        await stopWatch(routeKey: "member-rooms")
    }

    /// Inbox read-cursor sync — `room_members` for the signed-in user.
    func watchRoomReadCursors(
        userID: String,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        watch(
            WatchSpec(
                topic: "realtime:room-read-\(userID)",
                table: "room_members",
                filter: "user_id=eq.\(userID)",
                routeKey: "room-read:\(userID)",
                routeColumn: "room_id"
            ),
            accessToken: accessToken
        )
    }

    func stopWatchingRoomReadCursors(userID: String) async {
        await stopWatch(routeKey: "room-read:\(userID)")
    }

    private func watch(
        _ spec: WatchSpec,
        accessToken: String?
    ) -> AsyncStream<MessageRealtimeSignal> {
        AsyncStream { continuation in
            Task {
                try? await self.ensureConnected()
                self.lock.lock()
                self.continuations[spec.routeKey, default: []].append(continuation)
                self.specsByRouteKey[spec.routeKey] = spec
                let needsJoin = !self.joinedTopics.contains(spec.topic)
                if needsJoin {
                    self.joinedTopics.insert(spec.topic)
                }
                self.lock.unlock()
                if needsJoin {
                    await self.joinChannel(spec, accessToken: accessToken)
                }
                continuation.onTermination = { _ in }
            }
        }
    }

    private func stopWatch(routeKey: String) async {
        lock.lock()
        let continuations = continuations.removeValue(forKey: routeKey) ?? []
        let spec = specsByRouteKey.removeValue(forKey: routeKey)
        if let topic = spec?.topic {
            joinedTopics.remove(topic)
        }
        lock.unlock()
        for continuation in continuations {
            continuation.finish()
        }
        if let spec {
            await leaveChannel(topic: spec.topic)
        }
    }

    private func ensureConnected() async throws {
        if isConnected { return }
        try await connect()
    }

    private func nextRef() -> String {
        lock.lock()
        refCounter += 1
        let value = refCounter
        lock.unlock()
        return String(value)
    }

    private func joinChannel(_ spec: WatchSpec, accessToken: String?) async {
        let ref = nextRef()
        let config: [String: Any] = [
            "broadcast": ["ack": false, "self": false],
            "presence": ["key": ""],
            "postgres_changes": [
                [
                    "event": "*",
                    "schema": "public",
                    "table": spec.table,
                    "filter": spec.filter,
                ],
            ],
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
        lock.lock()
        if receiveLoopRunning {
            lock.unlock()
            return
        }
        receiveLoopRunning = true
        lock.unlock()
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            lock.lock()
            let task = webSocketTask
            let connected = _isConnected
            lock.unlock()
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
        lock.lock()
        receiveLoopRunning = false
        _isConnected = false
        lock.unlock()
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let event = object["event"] as? String ?? ""
        guard event == "postgres_changes" || event == "INSERT" || event == "UPDATE" || event == "DELETE"
        else { return }

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

        let kind: MessageRealtimeSignal.Kind
        switch type.uppercased() {
        case "INSERT": kind = .insert
        case "UPDATE": kind = .update
        case "DELETE": kind = .delete
        default: kind = .insert
        }

        lock.lock()
        let specs = Array(specsByRouteKey.values)
        let allContinuations = continuations
        lock.unlock()

        for spec in specs {
            let scope = (record?[spec.routeColumn] as? String)
                ?? (oldRecord?[spec.routeColumn] as? String)
            // Inbox watches are filtered by user_id / multi-room `in` lists; route keys
            // do not end with the row's room/conversation id — match by route key instead.
            let scopedMatch: Bool
            if spec.routeKey.hasPrefix("dm-read:")
                || spec.routeKey.hasPrefix("room-read:")
                || spec.routeKey == "member-rooms"
            {
                scopedMatch = scope != nil
            } else {
                scopedMatch = scope.map { spec.routeKey.hasSuffix(":\($0)") } ?? false
            }
            guard scopedMatch else { continue }
            let signal = MessageRealtimeSignal(
                kind: kind,
                messageID: messageID,
                conversationID: scope
            )
            for continuation in allContinuations[spec.routeKey] ?? [] {
                continuation.yield(signal)
            }
        }
    }

    private func sendJSON(_ object: [String: Any]) async {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8)
        else { return }
        lock.lock()
        let task = webSocketTask
        lock.unlock()
        try? await task?.send(.string(text))
    }
}

/// Shared signal for DM `messages` and Trade Room `room_messages` postgres_changes.
nonisolated struct MessageRealtimeSignal: Sendable {
    enum Kind: String, Sendable {
        case insert
        case update
        case delete
    }

    var kind: Kind
    var messageID: String?
    /// Populated from the postgres_changes filter column (e.g. `conversation_id`).
    var conversationID: String? = nil
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
