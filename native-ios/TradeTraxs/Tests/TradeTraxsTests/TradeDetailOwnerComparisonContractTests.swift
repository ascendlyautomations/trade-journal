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
              "win_rate": 0.58,
              "avg_rr": 1.2,
              "avg_target_rr": 1.2,
              "avg_realized_rr": 0.95,
              "avg_hold_seconds": 900,
              "pnl_percentile": 72.5,
              "rr_percentile": 60,
              "target_rr_percentile": 60,
              "realized_rr_percentile": 55,
              "hold_shorter_than_percent": 40,
              "long": { "trade_count": 7, "win_rate": 0.6, "avg_pnl": 55 },
              "short": { "trade_count": 5, "win_rate": 0.5, "avg_pnl": 30 }
            },
            "cohorts": {
              "all": {
                "trade_count": 12,
                "avg_pnl": 45.5,
                "win_rate": 0.58,
                "avg_target_rr": 1.2,
                "avg_realized_rr": 0.95,
                "avg_hold_seconds": 900,
                "pnl_percentile": 72.5,
                "target_rr_percentile": 60,
                "realized_rr_percentile": 55
              },
              "account_mode": null,
              "setup": null,
              "session": null
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
              "recent_trade_count": 3,
              "long": { "trade_count": 2, "win_rate": 1, "avg_pnl": 80, "total_pnl": 160 },
              "short": { "trade_count": 1, "win_rate": 0, "avg_pnl": -40, "total_pnl": -40 },
              "sessions": [
                { "session": "NY AM", "trade_count": 2, "win_rate": 1, "avg_pnl": 60 }
              ],
              "window_30d": {
                "trade_count": 2,
                "win_rate": 0.5,
                "total_pnl": 40,
                "avg_pnl": 20,
                "profit_factor": 1.2
              },
              "window_90d": null
            }
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TradeDetailOwnerComparisonBootstrapV1.self, from: json)
        XCTAssertEqual(decoded.data.cohort?.trade_count, 12)
        XCTAssertEqual(decoded.data.cohort?.avg_target_rr, 1.2)
        XCTAssertEqual(decoded.data.cohorts?.all?.trade_count, 12)
        XCTAssertEqual(decoded.data.ticker_history?.ticker, "MNQ")
        XCTAssertEqual(decoded.data.ticker_history?.window_30d?.trade_count, 2)
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
