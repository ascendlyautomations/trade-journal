import XCTest
@testable import TradeTraxs

final class BrokerIntegrationDecodingTests: XCTestCase {
    private var decoder: JSONDecoder {
        let json = JSONDecoder()
        json.keyDecodingStrategy = .useDefaultKeys
        return json
    }

    func testDecodesProductionConnectionsPayload() throws {
        let json = """
        {
          "provider": "tradovate",
          "connectionCount": 1,
          "connections": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "provider": "tradovate",
              "connected": true,
              "status": "connected",
              "label": "Tradovate Connection 1",
              "connected_at": "2026-01-01T00:00:00.000Z",
              "last_sync_at": null,
              "provider_user_id": "user-1",
              "provider_display_name": "Demo User",
              "connection_label": null,
              "api_environment": "demo"
            }
          ]
        }
        """.data(using: .utf8)!
        let decoded = try decoder.decode(TradovateConnectionsResponse.self, from: json)
        XCTAssertEqual(decoded.connectionCount, 1)
        XCTAssertEqual(decoded.connections.count, 1)
        XCTAssertEqual(decoded.connections[0].status, .connected)
        XCTAssertTrue(decoded.connections[0].isActiveForBrokerUI)
    }

    func testDecodesProductionAccountsPayload() throws {
        let json = """
        {
          "connectionId": "11111111-1111-1111-1111-111111111111",
          "state": "connected",
          "connectionStatus": "connected",
          "accounts": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "provider": "tradovate",
              "externalAccountId": "EXT-1",
              "externalAccountName": "Acct",
              "externalDisplayName": null,
              "metadata": {},
              "tradetraxsAccountId": null,
              "tradetraxsAccountName": null,
              "syncEnabled": true,
              "status": "discovered",
              "discoveredAt": "2026-01-01T00:00:00.000Z",
              "lastSeenAt": "2026-01-02T00:00:00.000Z",
              "lastSyncSuccessAt": null,
              "lastSyncStatus": "never",
              "autoSyncEnabled": true,
              "lastAutoSyncAt": null,
              "lastBrokerEventAt": null
            }
          ],
          "listener": null
        }
        """.data(using: .utf8)!
        let decoded = try decoder.decode(TradovateConnectionAccountsResponse.self, from: json)
        XCTAssertEqual(decoded.accounts.count, 1)
        XCTAssertEqual(decoded.accounts[0].externalAccountId, "EXT-1")
    }

    func testDecodesNativeAuthorizePayload() throws {
        let json = """
        { "ok": true, "authorizeUrl": "https://trader.tradovate.com/oauth/authorize?state=abc" }
        """.data(using: .utf8)!
        let decoded = try decoder.decode(TradovateAuthorizeNativeResponse.self, from: json)
        XCTAssertTrue(decoded.ok)
        XCTAssertNotNil(decoded.resolvedAuthorizeURLString)
    }
}
