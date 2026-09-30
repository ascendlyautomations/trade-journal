import XCTest
@testable import TradeTraxs

final class UserFacingSanitizationTests: XCTestCase {
    func testDecodingErrorMapsToFriendlyCopy() {
        struct Probe: Decodable {
            var value: Int
        }
        let json = Data("{}".utf8)
        let error: Error
        do {
            _ = try JSONDecoder().decode(Probe.self, from: json)
            XCTFail("Expected decode failure")
            return
        } catch let caught {
            error = caught
        }
        XCTAssertEqual(
            UserFacingError.message(for: error),
            "Unable to load this content. Please try again."
        )
    }

    func testSwiftDecodingDescriptionIsSanitized() {
        let raw = "The data couldn't be read because it isn't in the correct format."
        let message = UserFacingError.message(
            for: AppError.unknown(message: raw)
        )
        XCTAssertEqual(message, "Unable to load this content. Please try again.")
    }

    func testPlatformUpdatesDeployMessageIsSanitized() {
        let message = UserFacingError.message(
            for: AppError.unknown(
                message: "Platform updates API returned HTML instead of JSON (HTTP 502)."
            )
        )
        XCTAssertEqual(message, "Unable to load updates. Please try again.")
    }

    func testBrokerReconnectCopyIsPreserved() {
        let intentional = "Your Tradovate connection needs to be reconnected to continue syncing trades."
        let message = UserFacingError.message(for: AppError.unknown(message: intentional))
        XCTAssertEqual(message, intentional)
    }

    func testURLErrorOfflineMapsToConnectivityCopy() {
        let message = UserFacingError.message(
            for: URLError(.notConnectedToInternet)
        )
        XCTAssertTrue(message.contains("connection"))
    }
}
