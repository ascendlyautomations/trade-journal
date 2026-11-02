import XCTest
@testable import TradeTraxs

final class DetailLoadFailureSupportTests: XCTestCase {
    func testNotFoundMapsToUnavailableNotDeleted() {
        let error = AppError.unknown(message: "We couldn't find that.")
        let presentation = DetailLoadFailureSupport.presentation(for: error, content: .post)
        XCTAssertEqual(presentation.message, "This content is unavailable.")
        XCTAssertFalse(presentation.isRetryable)
    }

    func testConfirmedDeletedUsesDeletedCopy() {
        let presentation = DetailLoadFailureSupport.presentation(
            for: AppError.domain(.notFound(entity: "post", id: "x")),
            content: .post,
            confirmedDeleted: true
        )
        XCTAssertEqual(presentation.message, "This post was deleted.")
        XCTAssertFalse(presentation.isRetryable)
    }

    func testRetryableNetworkError() {
        let presentation = DetailLoadFailureSupport.presentation(
            for: AppError.transport(.timeout),
            content: .post
        )
        XCTAssertEqual(presentation.message, "Couldn't load. Try again.")
        XCTAssertTrue(presentation.isRetryable)
    }

    func testNotImplementedIsUnsupported() {
        let presentation = DetailLoadFailureSupport.presentation(
            for: AppError.notImplemented(feature: "x"),
            content: .post
        )
        XCTAssertEqual(presentation.message, "This content is unavailable.")
        XCTAssertFalse(presentation.isRetryable)
    }
}
