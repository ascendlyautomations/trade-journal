import XCTest
@testable import TradeTraxs

final class BrokerImportActionAvailabilityTests: XCTestCase {
    private var decoder: JSONDecoder { JSONDecoder() }

    private func decodeConnection(_ json: String) throws -> TradovateConnectionSummary {
        try decoder.decode(TradovateConnectionSummary.self, from: Data(json.utf8))
    }

    private func decodeAccount(_ json: String) throws -> BrokerIntegrationAccount {
        try decoder.decode(BrokerIntegrationAccount.self, from: Data(json.utf8))
    }

    func testMappedAccountOnReconnectRequiredConnectionShowsManualImportSection() throws {
        let connection = try decodeConnection(
            """
            {
              "id": "conn-1",
              "provider": "tradovate",
              "connected": false,
              "status": "reconnect_required",
              "label": "Tradovate"
            }
            """
        )
        let account = try decodeAccount(linkedAccountJSON(lastSyncStatus: "reconnect_required"))
        XCTAssertTrue(BrokerImportActionAvailability.showsManualImportSection(connection: connection, account: account))
    }

    func testConnectedMappedAccountShowsImportNotReconnect() throws {
        let connection = try decodeConnection(
            """
            {
              "id": "conn-1",
              "provider": "tradovate",
              "connected": true,
              "status": "connected",
              "label": "Tradovate"
            }
            """
        )
        let account = try decodeAccount(linkedAccountJSON(lastSyncStatus: "success"))
        XCTAssertTrue(BrokerImportActionAvailability.showsManualImportSection(connection: connection, account: account))
        XCTAssertFalse(
            BrokerImportActionAvailability.prefersReconnectAction(
                connection: connection,
                account: account,
                sessionReconnectMappingId: nil
            )
        )
    }

    func testReconnectRequiredAfterRelaunchWithoutSessionPrompt() throws {
        let connection = try decodeConnection(
            """
            {
              "id": "conn-1",
              "provider": "tradovate",
              "connected": false,
              "status": "reconnect_required",
              "label": "Tradovate"
            }
            """
        )
        let account = try decodeAccount(linkedAccountJSON(lastSyncStatus: "error"))
        XCTAssertTrue(
            BrokerImportActionAvailability.prefersReconnectAction(
                connection: connection,
                account: account,
                sessionReconnectMappingId: nil
            )
        )
    }

    func testFailedImportOnHealthyConnectionShowsRetryLabel() throws {
        let connection = try decodeConnection(
            """
            {
              "id": "conn-1",
              "provider": "tradovate",
              "connected": true,
              "status": "connected",
              "label": "Tradovate"
            }
            """
        )
        let account = try decodeAccount(linkedAccountJSON(lastSyncStatus: "error"))
        XCTAssertTrue(
            BrokerImportActionAvailability.showsRetryImportLabel(connection: connection, account: account)
        )
    }

    func testPersistedSyncingShowsBusyState() throws {
        let account = try decodeAccount(linkedAccountJSON(lastSyncStatus: "syncing"))
        XCTAssertTrue(BrokerImportActionAvailability.isSyncInProgressFromPersisted(account: account))
    }

    func testDashboardImportEntryWhenReconnectRequiredAndMapped() {
        let response = BrokerImportEligibilityResponse(
            eligible: false,
            optOut: false,
            connectionCount: 1,
            linkedAccountCount: 1,
            linkedAccounts: [
                BrokerImportEligibilityTarget(
                    provider: .tradovate,
                    mappingId: "map-1",
                    connectionId: "conn-1",
                    brokerAccountLabel: "Eval",
                    tradetraxsAccountName: "Eval 50K"
                ),
            ],
            hasSupportedConnection: false,
            hasLinkedAccount: true,
            canImportImmediately: true,
            needsAccountLinking: false
        )
        XCTAssertTrue(BrokerImportActionAvailability.showsDashboardImportEntry(from: response))
        XCTAssertTrue(response.resolvedHasSupportedConnection)
    }

    func testDashboardImportEntryHiddenWhenOptedOut() {
        let response = BrokerImportEligibilityResponse(
            eligible: false,
            optOut: true,
            connectionCount: 1,
            linkedAccountCount: 1,
            linkedAccounts: [
                BrokerImportEligibilityTarget(
                    provider: .tradovate,
                    mappingId: "map-1",
                    connectionId: "conn-1",
                    brokerAccountLabel: "Eval",
                    tradetraxsAccountName: nil
                ),
            ],
            hasSupportedConnection: true
        )
        XCTAssertFalse(BrokerImportActionAvailability.showsDashboardImportEntry(from: response))
    }

    func testDashboardImportEntryFromConnectionCountWhenApiFlagFalse() {
        let response = BrokerImportEligibilityResponse(
            eligible: false,
            optOut: false,
            connectionCount: 1,
            linkedAccountCount: 0,
            linkedAccounts: [],
            hasSupportedConnection: false,
            needsAccountLinking: false
        )
        XCTAssertTrue(BrokerImportActionAvailability.showsDashboardImportEntry(from: response))
    }

    func testUnmappedAccountDoesNotShowManualImportSection() throws {
        let connection = try decodeConnection(
            """
            {
              "id": "conn-1",
              "provider": "tradovate",
              "connected": true,
              "status": "connected",
              "label": "Tradovate"
            }
            """
        )
        let account = try decodeAccount(
            """
            {
              "id": "map-1",
              "provider": "tradovate",
              "external_account_id": "123",
              "sync_enabled": true,
              "status": "discovered",
              "discovered_at": "",
              "last_seen_at": ""
            }
            """
        )
        XCTAssertFalse(BrokerImportActionAvailability.showsManualImportSection(connection: connection, account: account))
    }

    private func linkedAccountJSON(lastSyncStatus: String) -> String {
        """
        {
          "id": "map-1",
          "provider": "tradovate",
          "external_account_id": "123",
          "tradetraxs_account_id": "tt-1",
          "sync_enabled": true,
          "status": "linked",
          "discovered_at": "",
          "last_seen_at": "",
          "last_sync_status": "\(lastSyncStatus)"
        }
        """
    }
}
