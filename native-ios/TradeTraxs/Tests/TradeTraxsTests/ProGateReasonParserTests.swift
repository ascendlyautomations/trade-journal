import XCTest
@testable import TradeTraxs

final class ProGateReasonParserTests: XCTestCase {
    func testLegacyDailyTradeLimitMapsToReason() {
        let reason = ProGateReasonParser.reason(
            from: AppError.unknown(message: "FREE_PLAN_DAILY_TRADE_LIMIT")
        )
        guard case .limit(.dailyTrades)? = reason else {
            return XCTFail("Expected daily_trades limit")
        }
    }

    func testStructuredProLimitPayload() {
        let json = """
        {"code":"PRO_LIMIT_REACHED","limit":"daily_posts","message":"cap"}
        """
        let reason = ProGateReasonParser.reason(from: AppError.unknown(message: json))
        guard case .limit(.dailyPosts)? = reason else {
            return XCTFail("Expected daily_posts")
        }
    }

    func testCopyTradingFeatureMessage() {
        let reason = ProGateReasonParser.reason(
            from: AppError.unknown(message: "Copy trading requires TraxPro.")
        )
        guard case .feature(.copyTrading)? = reason else {
            return XCTFail("Expected copy_trading feature")
        }
    }

    func testStalePublicTradeCopyIsNotMapped() {
        XCTAssertNil(
            ProGateReasonParser.reason(
                from: AppError.unknown(message: "Free plan allows only 1 public trade per day")
            )
        )
    }

    func testNetworkErrorIsNotProGate() {
        XCTAssertNil(
            ProGateReasonParser.reason(from: URLError(.notConnectedToInternet))
        )
    }
}
