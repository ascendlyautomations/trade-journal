import Foundation

/// Messaging inbox V2 bootstrap — `rpc_v2_messaging_bootstrap`.
nonisolated struct MessagingRpcBootstrapRepository: MessagesBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadMessagesBootstrap() async throws -> MessagesBootstrapV1 {
        try await loadMessagesBootstrap(cursor: nil, limit: 40, markNotificationsRead: true)
    }

    func loadMessagesBootstrap(
        cursor: String?,
        limit: Int,
        markNotificationsRead: Bool
    ) async throws -> MessagesBootstrapV1 {
        let args = MessagingRpcArguments(
            p_limit: limit,
            p_cursor: cursor,
            p_mark_message_notifications_read: markNotificationsRead
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .messaging,
            argumentsJSON: body,
            as: MessagesBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.messages.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct MessagingRpcArguments: Encodable, Sendable {
    var p_limit: Int
    var p_cursor: String?
    var p_mark_message_notifications_read: Bool

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor
        case p_mark_message_notifications_read
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
        try container.encode(p_mark_message_notifications_read, forKey: .p_mark_message_notifications_read)
    }
}

enum MessagingInboxFreshness {
    static let softStaleSeconds: TimeInterval = 10 * 60

    static func isSoftStale(lastLoadedAt: Date?) -> Bool {
        guard let lastLoadedAt else { return true }
        return Date().timeIntervalSince(lastLoadedAt) > softStaleSeconds
    }
}

enum MessagingBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    struct LoadResult: Sendable {
        var bootstrap: MessagesBootstrapV1
        var rpcRequestCount: Int
    }

    @MainActor
    static func loadInbox(
        viewerID: ProfileID,
        rpc: any RPCClient,
        inboxStore: MessagesInboxStore,
        detailCache: DetailPresentationCache,
        forceNetwork: Bool,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64,
        owner: String = "MessagingBootstrapLoader",
        authGeneration: UInt64 = 0,
        viewVisible: Bool = true
    ) async throws -> LoadResult {
        guard BackendV2FeatureFlags.isEnabled(.messages) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.messaging.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        await SessionNetworkGate.shared.awaitReady()

        let flightKey = BackendV2FlightKeys.messaging(viewerID: viewerID.rawValue, cursor: nil)
        let replacementActive = await BackendV2SingleFlight.shared.hasInFlight(key: flightKey)
        SafeInboxLog.bootstrapStarted(
            owner: owner,
            loadGeneration: loadGeneration,
            flightKey: flightKey,
            forceNetwork: forceNetwork,
            replacementActive: replacementActive
        )

        do {
            let bootstrap = try await fetchRPC(
                viewerID: viewerID.rawValue,
                rpc: rpc,
                flightKey: flightKey,
                markNotificationsRead: !forceNetwork
            )
            guard currentGeneration() == loadGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            try MessagingBootstrapApplier.apply(bootstrap, inboxStore: inboxStore, detailCache: detailCache)
            SafeInboxLog.bootstrapCompleted(
                owner: owner,
                loadGeneration: loadGeneration,
                conversationCount: inboxStore.conversations.count,
                rpcRequestCount: 1
            )
            return LoadResult(bootstrap: bootstrap, rpcRequestCount: 1)
        } catch {
            let diagnostic = MessagesBootstrapFailureDiagnostic.make(error: error)
            SafeInboxLog.bootstrapFailed(
                owner: owner,
                loadGeneration: loadGeneration,
                authGeneration: authGeneration,
                flightKey: flightKey,
                diagnostic: diagnostic,
                replacementActive: false,
                viewVisible: viewVisible
            )
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue)
                throw LoaderError.rpcUnavailable
            }
            throw error
        }
    }

    private static func fetchRPC(
        viewerID: String,
        rpc: any RPCClient,
        flightKey: String,
        markNotificationsRead: Bool
    ) async throws -> MessagesBootstrapV1 {
        let data = try await BootstrapTransportTimeout.run {
            try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = MessagingRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.loadMessagesBootstrap(
                    cursor: nil,
                    limit: 40,
                    markNotificationsRead: markNotificationsRead
                )
                return try JSONEncoder().encode(value)
            }
        }
        return try JSONDecoder().decode(MessagesBootstrapV1.self, from: data)
    }
}
