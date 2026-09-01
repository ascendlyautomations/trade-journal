import Foundation

nonisolated struct CalendarRpcBootstrapRepository {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func load(
        year: Int,
        month: Int,
        accountID: String?,
        entryFrom: Date,
        entryTo: Date
    ) async throws -> CalendarBootstrapV1 {
        let args = CalendarRpcArguments(
            p_year: year,
            p_month: month,
            p_account_id: accountID,
            p_entry_from: ISO8601.string(from: entryFrom),
            p_entry_to: ISO8601.string(from: entryTo)
        )
        let body = try JSONEncoder().encode(args)
        let value = try await client.call(
            .calendar,
            argumentsJSON: body,
            as: CalendarBootstrapV1.self,
            options: BackendV2RPCCallOptions(
                cacheMiss: true,
                flagName: BackendV2FeatureFlag.calendar.dottedName
            )
        )
        try value.validateContractVersion()
        return value
    }
}

private nonisolated struct CalendarRpcArguments: Encodable, Sendable {
    var p_year: Int
    var p_month: Int
    var p_account_id: String?
    var p_entry_from: String
    var p_entry_to: String

    enum CodingKeys: String, CodingKey {
        case p_year
        case p_month
        case p_account_id
        case p_entry_from
        case p_entry_to
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_year, forKey: .p_year)
        try container.encode(p_month, forKey: .p_month)
        if let p_account_id, !p_account_id.isEmpty {
            try container.encode(p_account_id, forKey: .p_account_id)
        } else {
            try container.encodeNil(forKey: .p_account_id)
        }
        try container.encode(p_entry_from, forKey: .p_entry_from)
        try container.encode(p_entry_to, forKey: .p_entry_to)
    }
}

enum CalendarBootstrapLoader {
    enum LoaderError: Error, Sendable {
        case flagOff
        case rpcUnavailable
        case invalidWindow
    }

    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        detailCache: DetailPresentationCache,
        year: Int,
        month: Int,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date
    ) async throws -> CalendarBootstrapApplier.Applied {
        guard BackendV2FeatureFlags.isEnabled(.calendar) else {
            throw LoaderError.flagOff
        }

        let rpcName = BackendV2Versioning.RPCName.calendar.rawValue
        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: viewerID.rawValue) {
            throw LoaderError.rpcUnavailable
        }

        let accountKey = accountID?.rawValue
        let flightKey = BackendV2FlightKeys.calendar(
            viewerID: viewerID.rawValue,
            year: year,
            month: month,
            accountID: accountKey
        )
        let bootstrap: CalendarBootstrapV1
        do {
            let data = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                let repo = CalendarRpcBootstrapRepository(rpc: rpc)
                let value = try await repo.load(
                    year: year,
                    month: month,
                    accountID: accountKey,
                    entryFrom: entryFrom,
                    entryTo: entryTo
                )
                return try JSONEncoder().encode(value)
            }
            bootstrap = try JSONDecoder().decode(CalendarBootstrapV1.self, from: data)
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

        return CalendarBootstrapApplier.apply(
            bootstrap,
            ownerID: viewerID,
            detailCache: detailCache
        )
    }
}
