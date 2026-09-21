import XCTest
@testable import TradeTraxs

/// Regression: production RPC must emit ISO `meta.server_time` string (not JSON timestamp object).
final class TradeDetailOwnerComparisonContractTests: XCTestCase {
    func testDecodesProductionMetaServerTimeString() throws {
        let json = """
        {
          "meta": {
            "contract_version": "v1",
            "server_time": "2026-09-21T22:15:30.123Z",
            "viewer_id": "11111111-1111-1111-1111-111111111111"
          },
          "data": {
            "cohort": null,
            "ticker_history": null
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TradeDetailOwnerComparisonBootstrapV1.self, from: json)
        XCTAssertEqual(decoded.meta.server_time, "2026-09-21T22:15:30.123Z")
        XCTAssertNil(decoded.data.cohort)
        XCTAssertNil(decoded.data.ticker_history)
        try decoded.validateContractVersion()
    }

    func testDecodesLegacyJsonTimestampServerTimeFails() {
        let json = """
        {
          "meta": {
            "contract_version": "v1",
            "server_time": "2026-09-21T22:15:30.123+00:00",
            "viewer_id": "11111111-1111-1111-1111-111111111111"
          },
          "data": { "cohort": null, "ticker_history": null }
        }
        """.data(using: .utf8)!

        XCTAssertNoThrow(try JSONDecoder().decode(TradeDetailOwnerComparisonBootstrapV1.self, from: json))
    }

    func testDecodesCohortAndTickerPayload() throws {
        let json = """
        {
          "meta": {
            "contract_version": "v1",
            "server_time": "2026-09-21T22:15:30.123Z",
            "viewer_id": "11111111-1111-1111-1111-111111111111"
          },
          "data": {
            "cohort": {
              "trade_count": 12,
              "avg_pnl": 45.5,
              "avg_rr": 1.2,
              "avg_hold_seconds": 900,
              "pnl_percentile": 72.5,
              "rr_percentile": 60,
              "hold_shorter_than_percent": 40
            },
            "ticker_history": {
              "ticker": "MNQ",
              "previous_trade_count": 3,
              "win_rate": 0.6666666667,
              "total_pnl": 120,
              "profit_factor": 2.1,
              "avg_trade_pnl": 40,
              "better_than_count": 1,
              "recent_wins": 2,
              "recent_trade_count": 3
            }
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TradeDetailOwnerComparisonBootstrapV1.self, from: json)
        XCTAssertEqual(decoded.data.cohort?.trade_count, 12)
        XCTAssertEqual(decoded.data.ticker_history?.ticker, "MNQ")
    }

    func testJsonObjectServerTimeIsDecodeFailure() {
        let json = """
        {
          "meta": {
            "contract_version": "v1",
            "server_time": { "iso": "2026-09-21T22:15:30.123Z" },
            "viewer_id": "11111111-1111-1111-1111-111111111111"
          },
          "data": { "cohort": null, "ticker_history": null }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(TradeDetailOwnerComparisonBootstrapV1.self, from: json))
    }
}
