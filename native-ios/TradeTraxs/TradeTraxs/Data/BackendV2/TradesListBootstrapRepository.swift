import Foundation

nonisolated struct TradesListRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(
        query: TradeHistoryQuery,
        limit: Int,
        cursor: String?
    ) async throws -> TradesListBootstrapV1 {
        let args = TradesListRpcArguments(query: query, limit: limit, cursor: cursor)
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .tradesList,
            argumentsJSON: body,
            as: TradesListBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.tradesList.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct TradesListRpcArguments: Encodable, Sendable {
    var p_limit: Int
    var p_cursor: String?
    var p_account_id: String?
    var p_search: String?
    var p_sort: String
    var p_created_from: String?
    var p_created_to: String?
    var p_result: String
    var p_pnl_min: Double?
    var p_pnl_max: Double?
    var p_direction: String
    var p_visibility: String

    init(query: TradeHistoryQuery, limit: Int, cursor: String?) {
        let filters = query.filters
        p_limit = limit
        p_cursor = cursor
        if case .account(let id) = filters.account {
            p_account_id = id.rawValue
        } else {
            p_account_id = nil
        }
        let search = query.trimmedSearch
        p_search = search.isEmpty ? nil : search
        p_sort = Self.sortParam(filters.sort)
        let bounds = filters.createdAtBounds()
        p_created_from = bounds.start.map { ISO8601.string(from: $0) }
        p_created_to = bounds.end.map { ISO8601.string(from: $0) }
        p_result = filters.result.rawValue
        p_pnl_min = filters.pnlMin.map { NSDecimalNumber(decimal: $0).doubleValue }
        p_pnl_max = filters.pnlMax.map { NSDecimalNumber(decimal: $0).doubleValue }
        p_direction = filters.direction.rawValue
        p_visibility = filters.visibility.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor
        case p_account_id
        case p_search
        case p_sort
        case p_created_from
        case p_created_to
        case p_result
        case p_pnl_min
        case p_pnl_max
        case p_direction
        case p_visibility
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_limit, forKey: .p_limit)
        if let p_cursor, !p_cursor.isEmpty {
            try container.encode(p_cursor, forKey: .p_cursor)
        } else {
            try container.encodeNil(forKey: .p_cursor)
        }
        if let p_account_id, !p_account_id.isEmpty {
            try container.encode(p_account_id, forKey: .p_account_id)
        } else {
            try container.encodeNil(forKey: .p_account_id)
        }
        if let p_search, !p_search.isEmpty {
            try container.encode(p_search, forKey: .p_search)
        } else {
            try container.encodeNil(forKey: .p_search)
        }
        try container.encode(p_sort, forKey: .p_sort)
        if let p_created_from {
            try container.encode(p_created_from, forKey: .p_created_from)
        } else {
            try container.encodeNil(forKey: .p_created_from)
        }
        if let p_created_to {
            try container.encode(p_created_to, forKey: .p_created_to)
        } else {
            try container.encodeNil(forKey: .p_created_to)
        }
        try container.encode(p_result, forKey: .p_result)
        if let p_pnl_min {
            try container.encode(p_pnl_min, forKey: .p_pnl_min)
        } else {
            try container.encodeNil(forKey: .p_pnl_min)
        }
        if let p_pnl_max {
            try container.encode(p_pnl_max, forKey: .p_pnl_max)
        } else {
            try container.encodeNil(forKey: .p_pnl_max)
        }
        try container.encode(p_direction, forKey: .p_direction)
        try container.encode(p_visibility, forKey: .p_visibility)
    }

    private static func sortParam(_ sort: TradeHistorySort) -> String {
        switch sort {
        case .newest: return "newest"
        case .oldest: return "oldest"
        case .highestPnL: return "highest_pnl"
        case .lowestPnL: return "lowest_pnl"
        }
    }
}

enum TradesListBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        query: TradeHistoryQuery,
        limit: Int,
        cursor: String?
    ) async throws -> TradesListBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.tradesList) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.tradesList.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let queryKey = TradeHistorySessionStore.queryKey(
            profileID: viewerID,
            filters: query.filters,
            searchText: query.searchText
        )
        let flightKey = BackendV2FlightKeys.tradesList(
            viewerID: viewerID.rawValue,
            queryKey: queryKey,
            cursor: cursor
        )
        let bootstrap: TradesListBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = TradesListRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.load(query: query, limit: limit, cursor: cursor)
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(TradesListBootstrapV1.self, from: data)
            try bootstrap.validateContractVersion()
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

        return TradesListBootstrapApplier.apply(
            bootstrap,
            ownerID: viewerID,
            detailCache: detailCache
        )
    }
}
