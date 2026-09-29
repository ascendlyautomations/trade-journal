import XCTest
@testable import TradeTraxs

final class BrokerSyncFailureResolutionTests: XCTestCase {
    private var decoder: JSONDecoder { JSONDecoder() }

    func testReconnectRequiredFromStructuredCode() throws {
        let json = """
        {
          "ok": false,
          "connectionId": "c1",
          "mappingId": "m1",
          "code": "BROKER_RECONNECT_REQUIRED",
          "errorCode": "reconnect_required",
          "summary": {
            "ok": false,
            "status": "reconnect_required",
            "tradesCreated": 0,
            "tradesUpdated": 0,
            "newTradeIds": [],
            "updatedTradeIds": [],
            "error": "Tradovate authorization expired. Reconnect this connection.",
            "errorCode": "reconnect_required"
          },
          "accounts": []
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(TradovateAccountSyncResponse.self, from: json)
        XCTAssertEqual(BrokerSyncFailureResolution.from(response), .reconnectRequired)
        XCTAssertEqual(
            BrokerSyncPresentation.reconnectPrimaryActionTitle(),
            "Reconnect Account"
        )
    }

    func testRetryableProviderUnavailable() throws {
        let json = """
        {
          "ok": false,
          "connectionId": "c1",
          "mappingId": "m1",
          "code": "BROKER_TEMPORARILY_UNAVAILABLE",
          "summary": {
            "ok": false,
            "status": "error",
            "tradesCreated": 0,
            "tradesUpdated": 0,
            "newTradeIds": [],
            "updatedTradeIds": [],
            "errorCode": "provider_unavailable"
          },
          "accounts": []
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(TradovateAccountSyncResponse.self, from: json)
        XCTAssertEqual(BrokerSyncFailureResolution.from(response), .retryable)
    }

    func testNoAvailableTradeHistoryIsNotRetryable() throws {
        let json = """
        {
          "ok": true,
          "connectionId": "c1",
          "mappingId": "m1",
          "code": "BROKER_NO_AVAILABLE_TRADE_HISTORY",
          "summary": {
            "ok": true,
            "status": "idle",
            "tradesCreated": 0,
            "tradesUpdated": 0,
            "newTradeIds": [],
            "updatedTradeIds": [],
            "syncOutcome": "no_available_trade_history",
            "errorCode": "broker_no_available_trade_history"
          },
          "accounts": []
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(TradovateAccountSyncResponse.self, from: json)
        XCTAssertEqual(BrokerSyncFailureResolution.from(response), .noAvailableTradeHistory)
        XCTAssertTrue(BrokerSyncFailureResolution.isNoAvailableTradeHistory(response))
        XCTAssertEqual(
            BrokerSyncPresentation.noAvailableTradeHistoryTitle(),
            "No trades are currently available to import from Tradovate."
        )
    }

    func testSyncInProgressIsRetryable() throws {
        let json = """
        {
          "ok": false,
          "connectionId": "c1",
          "mappingId": "m1",
          "code": "BROKER_SYNC_IN_PROGRESS",
          "summary": {
            "ok": false,
            "status": "syncing",
            "tradesCreated": 0,
            "tradesUpdated": 0,
            "newTradeIds": [],
            "updatedTradeIds": []
          },
          "accounts": []
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(TradovateAccountSyncResponse.self, from: json)
        XCTAssertEqual(BrokerSyncFailureResolution.from(response), .retryable)
    }
}
