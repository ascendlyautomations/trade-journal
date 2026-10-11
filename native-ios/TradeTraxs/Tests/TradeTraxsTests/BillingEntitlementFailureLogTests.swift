import XCTest
@testable import TradeTraxs

final class BillingEntitlementFailureLogTests: XCTestCase {
    func testClassifiesHTTPFailuresWithoutResponseBody() {
        let server = BillingEntitlementFailureLog.classify(
            NetworkError.server(statusCode: 500, message: "{\"error\":\"Could not load profile\",\"token\":\"secret\"}")
        )
        XCTAssertEqual(server, BillingEntitlementFailureClassification(category: "server", httpStatus: "500"))

        let unauthorized = BillingEntitlementFailureLog.classify(NetworkError.unauthorized)
        XCTAssertEqual(unauthorized, BillingEntitlementFailureClassification(category: "unauthorized", httpStatus: "401"))

        let forbidden = BillingEntitlementFailureLog.classify(NetworkError.forbidden)
        XCTAssertEqual(forbidden, BillingEntitlementFailureClassification(category: "forbidden", httpStatus: "403"))

        let wrapped = BillingEntitlementFailureLog.classify(
            AppError.transport(.server(statusCode: 502, message: "Bearer secret-token"))
        )
        XCTAssertEqual(wrapped, BillingEntitlementFailureClassification(category: "server", httpStatus: "502"))
    }

    func testClassifiesDecodingConnectivityAndSession() {
        XCTAssertEqual(
            BillingEntitlementFailureLog.classify(NetworkError.decoding(message: "type mismatch")),
            BillingEntitlementFailureClassification(category: "decoding", httpStatus: "none")
        )
        XCTAssertEqual(
            BillingEntitlementFailureLog.classify(NetworkError.connectivity),
            BillingEntitlementFailureClassification(category: "connectivity", httpStatus: "none")
        )
        XCTAssertEqual(
            BillingEntitlementFailureLog.classify(NetworkError.timeout),
            BillingEntitlementFailureClassification(category: "timeout", httpStatus: "none")
        )
        XCTAssertEqual(
            BillingEntitlementFailureLog.classify(AppError.authentication(.sessionMissing)),
            BillingEntitlementFailureClassification(category: "sessionMissing", httpStatus: "none")
        )
        XCTAssertEqual(
            BillingEntitlementFailureLog.classify(AppError.authentication(.sessionExpired)),
            BillingEntitlementFailureClassification(category: "sessionExpired", httpStatus: "none")
        )
    }
}
