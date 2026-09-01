import Foundation

/// Personal thread V2 bootstrap — `rpc_v1_conversation_thread_bootstrap`.
nonisolated struct ConversationThreadRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadThreadBootstrap(
        conversationID: ConversationID,
        messageLimit: Int,
        cursor: String?,
        markRead: Bool
    ) async throws -> ConversationThreadBootstrapV1 {
        let args = ConversationThreadRpcArguments(
            p_conversation_id: conversationID.rawValue,
            p_message_limit: messageLimit,
            p_cursor: cursor,
            p_mark_read: markRead
        )
        let body = try JSONEncoder().encode(args)
        let value = try await BootstrapTransportTimeout.run {
            try await self.client.call(
                .conversationThread,
                argumentsJSON: body,
                as: ConversationThreadBootstrapV1.self,
                options: BackendV2RPCCallOptions(
                    cacheMiss: true,
                    flagName: BackendV2FeatureFlag.messageThreads.dottedName
                )
            )
        }
        try value.validateContractVersion()
        try value.validateRequiredFields()
        return value
    }
}

private nonisolated struct ConversationThreadRpcArguments: Encodable, Sendable {
    var p_conversation_id: String
    var p_message_limit: Int
    var p_cursor: String?
    var p_mark_read: Bool

    enum CodingKeys: String, CodingKey {
        case p_conversation_id
        case p_message_limit
        case p_cursor
        case p_mark_read
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_conversation_id, forKey: .p_conversation_id)
        try container.encode(p_message_limit, forKey: .p_message_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
        try container.encode(p_mark_read, forKey: .p_mark_read)
    }
}

enum ConversationThreadBootstrapLoader {
    enum LoadIntent: Sendable {
        case coldOpen
        case pagination
        case cacheRevalidation
    }

    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
        case staleResponse
    }

    struct LoadResult: Sendable {
        var applied: ConversationThreadBootstrapApplier.Applied
        var cacheHit: Bool
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        conversationID: ConversationID,
        cursor: String?,
        markRead: Bool,
        intent: LoadIntent,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        inboxStore: MessagesInboxStore,
        loadGeneration: UInt64,
        currentGeneration: () -> UInt64,
        forceNetwork: Bool = false
    ) async throws -> LoadResult {
        guard BackendV2FeatureFlags.isEnabled(.messageThreads) else {
            throw LoaderError.flagOff
        }

        let cacheKey = ConversationThreadSessionStore.cacheKey(
            viewerID: viewerID,
            conversationID: conversationID
        )

        if cursor == nil, !forceNetwork,
           let cached = ConversationThreadSessionStore.shared.restore(key: cacheKey),
           !cached.isSoftStale
        {
            return LoadResult(
                applied: ConversationThreadBootstrapApplier.Applied(
                    conversation: cached.conversation,
                    messages: cached.messages,
                    nextCursor: cached.nextCursor,
                    hasMoreMessages: cached.hasMoreMessages,
                    markReadApplied: false,
                    notificationsMarkedRead: 0,
                    skippedMessages: 0
                ),
                cacheHit: true
            )
        }

        let rpcName = BackendV2Versioning.RPCName.conversationThread.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let flightKey = BackendV2FlightKeys.conversationThread(
            viewerID: viewerID.rawValue,
            conversationID: conversationID.rawValue,
            cursor: cursor,
            markRead: markRead
        )

        let bootstrap: ConversationThreadBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = ConversationThreadRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.loadThreadBootstrap(
                    conversationID: conversationID,
                    messageLimit: ConversationThreadSessionStore.messageLimit,
                    cursor: cursor,
                    markRead: markRead
                )
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(ConversationThreadBootstrapV1.self, from: data)
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(
                    rpcName: rpcName,
                    viewerID: viewerID.rawValue
                )
                throw LoaderError.rpcUnavailable
            }
            throw error
        }

        guard loadGeneration == currentGeneration() else {
            throw LoaderError.staleResponse
        }

        let applied = try ConversationThreadBootstrapApplier.apply(
            bootstrap,
            conversationID: conversationID,
            viewerID: viewerID,
            detailCache: detailCache
        )

        ThreadMarkReadTelemetry.log(
            owner: "bootstrap",
            intent: telemetryIntent(intent, markRead: markRead),
            applied: applied.markReadApplied,
            conversationID: conversationID
        )

        if applied.markReadApplied {
            inboxStore.markRead(conversationID: conversationID)
            AppIconBadgeSync.refresh(animated: false)
        }

        if cursor == nil {
            ConversationThreadSessionStore.shared.saveMergedFirstPage(
                cacheKey: cacheKey,
                conversation: applied.conversation,
                incoming: applied.messages,
                nextCursor: applied.nextCursor,
                hasMoreMessages: applied.hasMoreMessages
            )
        }

        return LoadResult(applied: applied, cacheHit: false)
    }

    private static func telemetryIntent(_ intent: LoadIntent, markRead: Bool) -> String {
        switch intent {
        case .coldOpen: return markRead ? "open" : "open-no-mark"
        case .pagination: return "pagination"
        case .cacheRevalidation: return "revalidate"
        }
    }
}
