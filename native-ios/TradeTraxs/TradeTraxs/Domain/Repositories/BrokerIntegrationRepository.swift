import Foundation

nonisolated protocol BrokerIntegrationRepository: Sendable {
    func listTradovateConnections() async throws -> TradovateConnectionsResponse
    func beginTradovateNativeOAuth(reconnectConnectionId: String?) async throws -> URL
    func listTradovateAccounts(connectionId: String, forceRefresh: Bool) async throws -> TradovateConnectionAccountsResponse
    func linkTradovateAccount(
        connectionId: String,
        brokerIntegrationAccountId: String,
        tradetraxsAccountId: String
    ) async throws -> BrokerLinkAccountsResponse
    func createAndLinkTradovateAccount(
        connectionId: String,
        brokerIntegrationAccountId: String,
        draft: TradingAccountDraft
    ) async throws -> BrokerLinkAccountsResponse
    func syncTradovateAccount(connectionId: String, mappingId: String) async throws -> TradovateAccountSyncResponse
    func runBrokerImport(mappingIds: [String]) async throws -> BrokerManualImportResponse
    func importEligibility() async throws -> BrokerImportEligibilityResponse
    func disconnectTradovate(connectionId: String) async throws
}
