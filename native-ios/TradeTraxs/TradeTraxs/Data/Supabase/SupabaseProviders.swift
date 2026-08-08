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
        return base.appendingPathComponent("storage/v1/object/public/\(bucket)/\(cleaned)")
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

/// Realtime connection lifecycle only — no product channel subscriptions in Phase 4B.
nonisolated final class LiveSupabaseRealtimeProvider: SupabaseRealtimeProviding, @unchecked Sendable {
    private let configuration: AppConfiguration
    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var _isConnected = false
    private let session: URLSession

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
    }

    func disconnect() async {
        lock.lock()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        _isConnected = false
        lock.unlock()
    }
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
