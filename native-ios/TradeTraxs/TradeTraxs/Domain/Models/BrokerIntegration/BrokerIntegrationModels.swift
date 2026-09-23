import Foundation

nonisolated enum BrokerIntegrationProvider: String, Codable, Sendable, Hashable {
    case tradovate
    case rithmic
}

nonisolated enum BrokerConnectionStatus: String, Codable, Sendable, Hashable {
    case connected
    case disconnected
    case error
    case reconnectRequired = "reconnect_required"
}

nonisolated struct TradovateConnectionSummary: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var provider: BrokerIntegrationProvider
    var connected: Bool
    var status: BrokerConnectionStatus
    var label: String
    var connectedAt: String?
    var lastSyncAt: String?
    var providerUserId: String?
    var providerDisplayName: String?
    var connectionLabel: String?
    var apiEnvironment: String?
    var brokerLoginUsername: String?

    /// Matches BFF ``ACTIVE_STATUSES`` — list accounts even when OAuth token needs refresh.
    var isActiveForBrokerUI: Bool {
        switch status {
        case .connected, .reconnectRequired, .error:
            return true
        case .disconnected:
            return false
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case connected
        case status
        case label
        case connectedAt = "connected_at"
        case lastSyncAt = "last_sync_at"
        case providerUserId = "provider_user_id"
        case providerDisplayName = "provider_display_name"
        case connectionLabel = "connection_label"
        case apiEnvironment = "api_environment"
        case brokerLoginUsername = "broker_login_username"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(BrokerIntegrationProvider.self, forKey: .provider)
        connected = try container.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        if let parsed = try container.decodeIfPresent(BrokerConnectionStatus.self, forKey: .status) {
            status = parsed
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .status) {
            status = BrokerConnectionStatus(rawValue: raw) ?? .error
        } else {
            status = .disconnected
        }
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Tradovate Connection"
        connectedAt = try container.decodeIfPresent(String.self, forKey: .connectedAt)
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt)
        providerUserId = try container.decodeIfPresent(String.self, forKey: .providerUserId)
        providerDisplayName = try container.decodeIfPresent(String.self, forKey: .providerDisplayName)
        connectionLabel = try container.decodeIfPresent(String.self, forKey: .connectionLabel)
        apiEnvironment = try container.decodeIfPresent(String.self, forKey: .apiEnvironment)
        brokerLoginUsername = try container.decodeIfPresent(String.self, forKey: .brokerLoginUsername)
    }
}

nonisolated struct TradovateConnectionsResponse: Codable, Sendable {
    var provider: BrokerIntegrationProvider
    var connectionCount: Int
    var connections: [TradovateConnectionSummary]

    enum CodingKeys: String, CodingKey {
        case provider
        case connectionCount
        case connection_count
        case connections
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.data) {
            let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
            provider =
                try nested.decodeIfPresent(BrokerIntegrationProvider.self, forKey: .provider) ?? .tradovate
            let list = try nested.decode([TradovateConnectionSummary].self, forKey: .connections)
            connections = list
            if let count = try nested.decodeIfPresent(Int.self, forKey: .connectionCount) {
                connectionCount = count
            } else if let count = try nested.decodeIfPresent(Int.self, forKey: .connection_count) {
                connectionCount = count
            } else {
                connectionCount = list.count
            }
            return
        }
        provider =
            try container.decodeIfPresent(BrokerIntegrationProvider.self, forKey: .provider) ?? .tradovate
        let list = try container.decode([TradovateConnectionSummary].self, forKey: .connections)
        connections = list
        if let count = try container.decodeIfPresent(Int.self, forKey: .connectionCount) {
            connectionCount = count
        } else if let count = try container.decodeIfPresent(Int.self, forKey: .connection_count) {
            connectionCount = count
        } else {
            connectionCount = list.count
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(connectionCount, forKey: .connectionCount)
        try container.encode(connections, forKey: .connections)
    }
}

nonisolated enum BrokerIntegrationAccountStatus: String, Codable, Sendable, Hashable {
    case discovered
    case linked
    case inactive
}

nonisolated struct BrokerIntegrationAccount: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var provider: BrokerIntegrationProvider
    var externalAccountId: String
    var externalAccountName: String?
    var externalDisplayName: String?
    var metadata: [String: JSONBrokerValue]
    var tradetraxsAccountId: String?
    var tradetraxsAccountName: String?
    var syncEnabled: Bool
    var status: BrokerIntegrationAccountStatus
    var discoveredAt: String
    var lastSeenAt: String
    var lastSyncSuccessAt: String?
    var lastSyncStatus: String?
    var autoSyncEnabled: Bool?
    var lastAutoSyncAt: String?
    var lastBrokerEventAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case externalAccountId
        case external_account_id
        case externalAccountName
        case external_account_name
        case externalDisplayName
        case external_display_name
        case metadata
        case tradetraxsAccountId
        case tradetraxs_account_id
        case tradetraxsAccountName
        case tradetraxs_account_name
        case syncEnabled
        case sync_enabled
        case status
        case discoveredAt
        case discovered_at
        case lastSeenAt
        case last_seen_at
        case lastSyncSuccessAt
        case last_sync_success_at
        case lastSyncStatus
        case last_sync_status
        case autoSyncEnabled
        case auto_sync_enabled
        case lastAutoSyncAt
        case last_auto_sync_at
        case lastBrokerEventAt
        case last_broker_event_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(BrokerIntegrationProvider.self, forKey: .provider)
        externalAccountId =
            try container.decodeIfPresent(String.self, forKey: .externalAccountId)
            ?? container.decode(String.self, forKey: .external_account_id)
        externalAccountName =
            try container.decodeIfPresent(String.self, forKey: .externalAccountName)
            ?? container.decodeIfPresent(String.self, forKey: .external_account_name)
        externalDisplayName =
            try container.decodeIfPresent(String.self, forKey: .externalDisplayName)
            ?? container.decodeIfPresent(String.self, forKey: .external_display_name)
        metadata = try container.decodeIfPresent([String: JSONBrokerValue].self, forKey: .metadata) ?? [:]
        tradetraxsAccountId =
            try container.decodeIfPresent(String.self, forKey: .tradetraxsAccountId)
            ?? container.decodeIfPresent(String.self, forKey: .tradetraxs_account_id)
        tradetraxsAccountName =
            try container.decodeIfPresent(String.self, forKey: .tradetraxsAccountName)
            ?? container.decodeIfPresent(String.self, forKey: .tradetraxs_account_name)
        syncEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .syncEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .sync_enabled)
            ?? true
        if let parsed = try container.decodeIfPresent(BrokerIntegrationAccountStatus.self, forKey: .status) {
            status = parsed
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .status),
                  let parsed = BrokerIntegrationAccountStatus(rawValue: raw)
        {
            status = parsed
        } else {
            status = tradetraxsAccountId != nil ? .linked : .discovered
        }
        discoveredAt =
            try container.decodeIfPresent(String.self, forKey: .discoveredAt)
            ?? container.decodeIfPresent(String.self, forKey: .discovered_at)
            ?? ""
        lastSeenAt =
            try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
            ?? container.decodeIfPresent(String.self, forKey: .last_seen_at)
            ?? ""
        lastSyncSuccessAt =
            try container.decodeIfPresent(String.self, forKey: .lastSyncSuccessAt)
            ?? container.decodeIfPresent(String.self, forKey: .last_sync_success_at)
        lastSyncStatus =
            try container.decodeIfPresent(String.self, forKey: .lastSyncStatus)
            ?? container.decodeIfPresent(String.self, forKey: .last_sync_status)
        autoSyncEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .auto_sync_enabled)
        lastAutoSyncAt =
            try container.decodeIfPresent(String.self, forKey: .lastAutoSyncAt)
            ?? container.decodeIfPresent(String.self, forKey: .last_auto_sync_at)
        lastBrokerEventAt =
            try container.decodeIfPresent(String.self, forKey: .lastBrokerEventAt)
            ?? container.decodeIfPresent(String.self, forKey: .last_broker_event_at)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(externalAccountId, forKey: .externalAccountId)
        try container.encodeIfPresent(externalAccountName, forKey: .externalAccountName)
        try container.encodeIfPresent(externalDisplayName, forKey: .externalDisplayName)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(tradetraxsAccountId, forKey: .tradetraxsAccountId)
        try container.encodeIfPresent(tradetraxsAccountName, forKey: .tradetraxsAccountName)
        try container.encode(syncEnabled, forKey: .syncEnabled)
        try container.encode(status, forKey: .status)
        try container.encode(discoveredAt, forKey: .discoveredAt)
        try container.encode(lastSeenAt, forKey: .lastSeenAt)
        try container.encodeIfPresent(lastSyncSuccessAt, forKey: .lastSyncSuccessAt)
        try container.encodeIfPresent(lastSyncStatus, forKey: .lastSyncStatus)
        try container.encodeIfPresent(autoSyncEnabled, forKey: .autoSyncEnabled)
        try container.encodeIfPresent(lastAutoSyncAt, forKey: .lastAutoSyncAt)
        try container.encodeIfPresent(lastBrokerEventAt, forKey: .lastBrokerEventAt)
    }

    var isLinked: Bool { status == .linked || tradetraxsAccountId != nil }

    /// Authoritative mapping for manual import — matches Broker Integrations BFF rows.
    var hasTradetraxsMapping: Bool {
        guard let raw = tradetraxsAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !raw.isEmpty
    }

    var displayTitle: String {
        externalDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? externalAccountName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? externalAccountId
    }
}

/// Loose JSON metadata from broker discovery — never persisted locally as secrets.
nonisolated enum JSONBrokerValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONBrokerValue])
    case array([JSONBrokerValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONBrokerValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONBrokerValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

nonisolated struct TradovateConnectionAccountsResponse: Codable, Sendable {
    var connectionId: String
    var state: String
    var connectionStatus: String?
    var accounts: [BrokerIntegrationAccount]

    enum CodingKeys: String, CodingKey {
        case connectionId
        case connection_id
        case state
        case connectionStatus
        case connection_status
        case accounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionId =
            try container.decodeIfPresent(String.self, forKey: .connectionId)
            ?? container.decode(String.self, forKey: .connection_id)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? "unknown"
        connectionStatus =
            try container.decodeIfPresent(String.self, forKey: .connectionStatus)
            ?? container.decodeIfPresent(String.self, forKey: .connection_status)
        accounts = try container.decodeIfPresent([BrokerIntegrationAccount].self, forKey: .accounts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connectionId, forKey: .connectionId)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(connectionStatus, forKey: .connectionStatus)
        try container.encode(accounts, forKey: .accounts)
    }
}

nonisolated struct BrokerLinkAccountsResponse: Codable, Sendable {
    var ok: Bool
    var connectionId: String
    var accounts: [BrokerIntegrationAccount]
    var tradetraxsAccountId: String?
    var alreadyLinked: Bool?
}

nonisolated enum TradovateSyncRequestMode: String, Codable, Sendable {
    case preview
    case `import`
    case cancelPreview = "cancel_preview"
}

/// Server-computed broker trade row for Review Imported Trades (before confirm).
nonisolated struct TradovateImportPreviewTrade: Codable, Sendable, Hashable, Identifiable {
    var lifecycleKey: String
    var contractId: String
    var ticker: String
    var direction: String
    var contracts: Double
    var entryPrice: Double
    var exitPrice: Double
    var entryTime: String
    var exitTime: String
    var points: Double
    var pnl: Double?
    var grossPnl: Double?
    var fees: Double?

    var id: String { lifecycleKey }

    enum CodingKeys: String, CodingKey {
        case lifecycleKey
        case contractId
        case ticker
        case direction
        case contracts
        case entryPrice
        case exitPrice
        case entryTime
        case exitTime
        case points
        case pnl
        case grossPnl
        case fees
    }
}

nonisolated struct TradovateSyncSummaryPayload: Codable, Sendable {
    var ok: Bool
    var status: String
    var tradesCreated: Int
    var tradesUpdated: Int
    var newTradeIds: [String]
    var updatedTradeIds: [String]
    var importPreviewTrades: [TradovateImportPreviewTrade]
    var previewEligibleCount: Int?
    var persistCalled: Bool?
    var error: String?
    var errorCode: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case status
        case tradesCreated
        case tradesUpdated
        case newTradeIds
        case updatedTradeIds
        case importPreviewTrades
        case previewEligibleCount
        case persistCalled
        case error
        case errorCode
    }

    private enum SnakeCodingKeys: String, CodingKey {
        case trades_created
        case trades_updated
        case new_trade_ids
        case updated_trade_ids
        case import_preview_trades
        case preview_eligible_count
        case persist_called
        case error_code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let snake = try decoder.container(keyedBy: SnakeCodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "error"
        tradesCreated =
            try container.decodeIfPresent(Int.self, forKey: .tradesCreated)
            ?? snake.decodeIfPresent(Int.self, forKey: .trades_created)
            ?? 0
        tradesUpdated =
            try container.decodeIfPresent(Int.self, forKey: .tradesUpdated)
            ?? snake.decodeIfPresent(Int.self, forKey: .trades_updated)
            ?? 0
        newTradeIds =
            try container.decodeIfPresent([String].self, forKey: .newTradeIds)
            ?? snake.decodeIfPresent([String].self, forKey: .new_trade_ids)
            ?? []
        updatedTradeIds =
            try container.decodeIfPresent([String].self, forKey: .updatedTradeIds)
            ?? snake.decodeIfPresent([String].self, forKey: .updated_trade_ids)
            ?? []
        importPreviewTrades =
            try container.decodeIfPresent([TradovateImportPreviewTrade].self, forKey: .importPreviewTrades)
            ?? snake.decodeIfPresent([TradovateImportPreviewTrade].self, forKey: .import_preview_trades)
            ?? []
        previewEligibleCount =
            try container.decodeIfPresent(Int.self, forKey: .previewEligibleCount)
            ?? snake.decodeIfPresent(Int.self, forKey: .preview_eligible_count)
        persistCalled =
            try container.decodeIfPresent(Bool.self, forKey: .persistCalled)
            ?? snake.decodeIfPresent(Bool.self, forKey: .persist_called)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        errorCode =
            try container.decodeIfPresent(String.self, forKey: .errorCode)
            ?? snake.decodeIfPresent(String.self, forKey: .error_code)
    }
}

nonisolated struct TradovateAccountSyncResponse: Codable, Sendable {
    var ok: Bool
    var connectionId: String
    var mappingId: String
    var summary: TradovateSyncSummaryPayload
    var accounts: [BrokerIntegrationAccount]
    /// Stable BFF contract (`BROKER_RECONNECT_REQUIRED`, …).
    var code: String?
    var errorCode: String?
    var failureCategory: String?
    var failureStage: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case connectionId
        case mappingId
        case summary
        case accounts
        case code
        case errorCode
        case failureCategory
        case failureStage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        connectionId = try container.decodeIfPresent(String.self, forKey: .connectionId) ?? ""
        mappingId = try container.decodeIfPresent(String.self, forKey: .mappingId) ?? ""
        summary = try container.decode(TradovateSyncSummaryPayload.self, forKey: .summary)
        accounts = try container.decodeIfPresent([BrokerIntegrationAccount].self, forKey: .accounts) ?? []
        code = try container.decodeIfPresent(String.self, forKey: .code)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        failureCategory = try container.decodeIfPresent(String.self, forKey: .failureCategory)
        failureStage = try container.decodeIfPresent(String.self, forKey: .failureStage)
    }
}

nonisolated struct BrokerManualImportResponse: Codable, Sendable {
    var ok: Bool
    var newTradeIds: [String]
    var totalTradesCreated: Int
    var totalTradesUpdated: Int
}

nonisolated struct BrokerImportEligibilityConnectedProviders: Codable, Sendable, Hashable {
    var tradovate: Bool
    var rithmic: Bool
}

nonisolated struct BrokerImportEligibilityResponse: Codable, Sendable {
    var eligible: Bool
    var optOut: Bool
    var connectionCount: Int
    var linkedAccountCount: Int
    var linkedAccounts: [BrokerImportEligibilityTarget]
    var hasSupportedConnection: Bool?
    var hasLinkedAccount: Bool?
    var canImportImmediately: Bool?
    var needsAccountLinking: Bool?
    var connectedProviders: BrokerImportEligibilityConnectedProviders?

    enum CodingKeys: String, CodingKey {
        case eligible
        case optOut
        case opt_out
        case connectionCount
        case connection_count
        case linkedAccountCount
        case linked_account_count
        case linkedAccounts
        case linked_accounts
        case hasSupportedConnection
        case has_supported_connection
        case hasLinkedAccount
        case has_linked_account
        case canImportImmediately
        case can_import_immediately
        case needsAccountLinking
        case needs_account_linking
        case connectedProviders
        case connected_providers
    }

    init(
        eligible: Bool,
        optOut: Bool,
        connectionCount: Int,
        linkedAccountCount: Int,
        linkedAccounts: [BrokerImportEligibilityTarget],
        hasSupportedConnection: Bool? = nil,
        hasLinkedAccount: Bool? = nil,
        canImportImmediately: Bool? = nil,
        needsAccountLinking: Bool? = nil,
        connectedProviders: BrokerImportEligibilityConnectedProviders? = nil
    ) {
        self.eligible = eligible
        self.optOut = optOut
        self.connectionCount = connectionCount
        self.linkedAccountCount = linkedAccountCount
        self.linkedAccounts = linkedAccounts
        self.hasSupportedConnection = hasSupportedConnection
        self.hasLinkedAccount = hasLinkedAccount
        self.canImportImmediately = canImportImmediately
        self.needsAccountLinking = needsAccountLinking
        self.connectedProviders = connectedProviders
    }

    var resolvedHasSupportedConnection: Bool {
        hasSupportedConnection ?? (connectionCount > 0)
    }

    var resolvedHasLinkedAccount: Bool {
        hasLinkedAccount ?? (linkedAccountCount > 0 || !linkedAccounts.isEmpty)
    }

    var resolvedCanImportImmediately: Bool {
        canImportImmediately ?? resolvedHasLinkedAccount
    }

    var resolvedNeedsAccountLinking: Bool {
        if let needsAccountLinking { return needsAccountLinking }
        return resolvedHasSupportedConnection && !resolvedHasLinkedAccount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eligible = try container.decodeIfPresent(Bool.self, forKey: .eligible) ?? false
        optOut =
            try container.decodeIfPresent(Bool.self, forKey: .optOut)
            ?? container.decodeIfPresent(Bool.self, forKey: .opt_out)
            ?? false
        connectionCount =
            try container.decodeIfPresent(Int.self, forKey: .connectionCount)
            ?? container.decodeIfPresent(Int.self, forKey: .connection_count)
            ?? 0
        linkedAccountCount =
            try container.decodeIfPresent(Int.self, forKey: .linkedAccountCount)
            ?? container.decodeIfPresent(Int.self, forKey: .linked_account_count)
            ?? 0
        linkedAccounts =
            try container.decodeIfPresent([BrokerImportEligibilityTarget].self, forKey: .linkedAccounts)
            ?? container.decodeIfPresent([BrokerImportEligibilityTarget].self, forKey: .linked_accounts)
            ?? []
        hasSupportedConnection =
            try container.decodeIfPresent(Bool.self, forKey: .hasSupportedConnection)
            ?? container.decodeIfPresent(Bool.self, forKey: .has_supported_connection)
        hasLinkedAccount =
            try container.decodeIfPresent(Bool.self, forKey: .hasLinkedAccount)
            ?? container.decodeIfPresent(Bool.self, forKey: .has_linked_account)
        canImportImmediately =
            try container.decodeIfPresent(Bool.self, forKey: .canImportImmediately)
            ?? container.decodeIfPresent(Bool.self, forKey: .can_import_immediately)
        needsAccountLinking =
            try container.decodeIfPresent(Bool.self, forKey: .needsAccountLinking)
            ?? container.decodeIfPresent(Bool.self, forKey: .needs_account_linking)
        connectedProviders =
            try container.decodeIfPresent(BrokerImportEligibilityConnectedProviders.self, forKey: .connectedProviders)
            ?? container.decodeIfPresent(BrokerImportEligibilityConnectedProviders.self, forKey: .connected_providers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eligible, forKey: .eligible)
        try container.encode(optOut, forKey: .optOut)
        try container.encode(connectionCount, forKey: .connectionCount)
        try container.encode(linkedAccountCount, forKey: .linkedAccountCount)
        try container.encode(linkedAccounts, forKey: .linkedAccounts)
        try container.encodeIfPresent(hasSupportedConnection, forKey: .hasSupportedConnection)
        try container.encodeIfPresent(hasLinkedAccount, forKey: .hasLinkedAccount)
        try container.encodeIfPresent(canImportImmediately, forKey: .canImportImmediately)
        try container.encodeIfPresent(needsAccountLinking, forKey: .needsAccountLinking)
        try container.encodeIfPresent(connectedProviders, forKey: .connectedProviders)
    }
}

nonisolated struct BrokerImportEligibilityTarget: Codable, Sendable, Hashable, Identifiable {
    var provider: BrokerIntegrationProvider
    var mappingId: String
    var connectionId: String
    var brokerAccountLabel: String
    var tradetraxsAccountName: String?

    var id: String { mappingId }

    enum CodingKeys: String, CodingKey {
        case provider
        case mappingId
        case mapping_id
        case connectionId
        case connection_id
        case brokerAccountLabel
        case broker_account_label
        case tradetraxsAccountName
        case tradetraxs_account_name
    }

    init(
        provider: BrokerIntegrationProvider,
        mappingId: String,
        connectionId: String,
        brokerAccountLabel: String,
        tradetraxsAccountName: String?
    ) {
        self.provider = provider
        self.mappingId = mappingId
        self.connectionId = connectionId
        self.brokerAccountLabel = brokerAccountLabel
        self.tradetraxsAccountName = tradetraxsAccountName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(BrokerIntegrationProvider.self, forKey: .provider)
        mappingId =
            try container.decodeIfPresent(String.self, forKey: .mappingId)
            ?? container.decode(String.self, forKey: .mapping_id)
        connectionId =
            try container.decodeIfPresent(String.self, forKey: .connectionId)
            ?? container.decode(String.self, forKey: .connection_id)
        let label =
            try container.decodeIfPresent(String.self, forKey: .brokerAccountLabel)
            ?? container.decodeIfPresent(String.self, forKey: .broker_account_label)
        brokerAccountLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? label!
            : mappingId
        tradetraxsAccountName =
            try container.decodeIfPresent(String.self, forKey: .tradetraxsAccountName)
            ?? container.decodeIfPresent(String.self, forKey: .tradetraxs_account_name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(mappingId, forKey: .mappingId)
        try container.encode(connectionId, forKey: .connectionId)
        try container.encode(brokerAccountLabel, forKey: .brokerAccountLabel)
        try container.encodeIfPresent(tradetraxsAccountName, forKey: .tradetraxsAccountName)
    }
}

nonisolated struct TradovateAuthorizeNativeResponse: Codable, Sendable {
    var ok: Bool
    var authorizeUrl: String?
    var error: String?

    /// Accepts camelCase (`authorizeUrl`) and snake_case (`authorize_url`) from the BFF.
    var resolvedAuthorizeURLString: String? {
        let trimmed = authorizeUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case authorizeUrl
        case authorize_url
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        error = try container.decodeIfPresent(String.self, forKey: .error)
        let camel = try container.decodeIfPresent(String.self, forKey: .authorizeUrl)
        let snake = try container.decodeIfPresent(String.self, forKey: .authorize_url)
        authorizeUrl = camel ?? snake
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(authorizeUrl, forKey: .authorizeUrl)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

nonisolated enum TradovateBrokerOAuthOutcome: Sendable, Equatable {
    case success
    case cancelled
    case error(reason: String?)
}

// MARK: - Rithmic BFF

nonisolated struct RithmicConnectCapabilitiesResponse: Codable, Sendable {
    var userConnectEnabled: Bool
    var productionUserAuthConfirmed: Bool
    var apiEnvironment: String
    var showConnectUi: Bool
    var credentialModelStatus: String
}

nonisolated struct RithmicConnectResponse: Codable, Sendable {
    var ok: Bool
    var code: String?
    var userMessage: String?
    var systemNames: [String]?
    var connectionId: String?
    var systemName: String?
    var accountCount: Int?
    var reconnect: Bool?
}

nonisolated enum RithmicConnectOutcome: Sendable, Equatable {
    case connected(connectionId: String, systemName: String, accountCount: Int)
    case systemSelectionRequired(systemNames: [String], message: String)
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
