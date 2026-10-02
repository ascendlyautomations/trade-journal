import Foundation

/// Derives broker import / reconnect action visibility from persisted connection + account sync state.
nonisolated enum BrokerImportActionAvailability {
    /// Dashboard “Import From Broker” entry — shared with eligibility / import routing (not Settings-only).
    static func showsDashboardImportEntry(
        optOut: Bool,
        connectionCount: Int,
        linkedAccountCount: Int,
        linkedAccounts: [BrokerImportEligibilityTarget],
        apiHasSupportedConnection: Bool?
    ) -> Bool {
        guard !optOut else { return false }
        return showsBrokerImportEntryPoint(
            connectionCount: connectionCount,
            linkedAccountCount: linkedAccountCount,
            linkedAccounts: linkedAccounts,
            apiHasSupportedConnection: apiHasSupportedConnection
        )
    }

    static func showsDashboardImportEntry(from response: BrokerImportEligibilityResponse) -> Bool {
        showsDashboardImportEntry(
            optOut: response.optOut,
            connectionCount: response.connectionCount,
            linkedAccountCount: response.linkedAccountCount,
            linkedAccounts: response.linkedAccounts,
            apiHasSupportedConnection: response.hasSupportedConnection
        )
    }

    /// Any broker import entry path (import, reconnect, link accounts, retry) from persisted eligibility.
    static func showsBrokerImportEntryPoint(
        connectionCount: Int,
        linkedAccountCount: Int,
        linkedAccounts: [BrokerImportEligibilityTarget],
        apiHasSupportedConnection: Bool?
    ) -> Bool {
        if !linkedAccounts.isEmpty { return true }
        if linkedAccountCount > 0 { return true }
        if connectionCount > 0 { return true }
        return apiHasSupportedConnection ?? false
    }

    static func showsManualImportSection(
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount
    ) -> Bool {
        account.hasTradetraxsMapping && connection.isActiveForBrokerUI
    }

    static func prefersReconnectAction(
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount,
        sessionReconnectMappingId: String?
    ) -> Bool {
        if sessionReconnectMappingId == account.id { return true }
        if connection.status == .reconnectRequired { return true }
        if normalizedSyncStatus(account.lastSyncStatus) == "reconnect_required" { return true }
        return false
    }

    static func isSyncInProgressFromPersisted(account: BrokerIntegrationAccount) -> Bool {
        normalizedSyncStatus(account.lastSyncStatus) == "syncing"
    }

    static func showsRetryImportLabel(
        connection: TradovateConnectionSummary,
        account: BrokerIntegrationAccount
    ) -> Bool {
        guard connection.connected, !prefersReconnectAction(
            connection: connection,
            account: account,
            sessionReconnectMappingId: nil
        ) else { return false }
        switch normalizedSyncStatus(account.lastSyncStatus) {
        case "error", "partial":
            return true
        default:
            return false
        }
    }

    private static func normalizedSyncStatus(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
