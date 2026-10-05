import XCTest
@testable import TradeTraxs

final class SignInFormErrorPresentationTests: XCTestCase {
    func testInvalidCredentialsCopy() {
        XCTAssertEqual(
            SignInFormErrorPresentation.inlineMessage(for: AuthenticationError.invalidCredentials),
            SignInFormErrorPresentation.incorrectCredentials
        )
    }

    func testNetworkAndTimeoutCopy() {
        XCTAssertEqual(
            SignInFormErrorPresentation.inlineMessage(
                for: AuthenticationError.unknown(SignInFormErrorPresentation.Reason.networkUnavailable)
            ),
            SignInFormErrorPresentation.networkUnavailable
        )
        XCTAssertEqual(
            SignInFormErrorPresentation.inlineMessage(
                for: AuthenticationError.unknown(SignInFormErrorPresentation.Reason.timedOut)
            ),
            SignInFormErrorPresentation.timedOut
        )
    }

    func testBootstrapIncompleteCopy() {
        XCTAssertEqual(
            SignInFormErrorPresentation.inlineMessage(
                for: AuthenticationError.unknown(SignInFormErrorPresentation.Reason.sessionNotReady)
            ),
            SignInFormErrorPresentation.bootstrapIncomplete
        )
    }

    func testAppleFailureCopy() {
        XCTAssertEqual(
            SignInFormErrorPresentation.inlineMessage(for: AuthenticationError.providerUnavailable(.apple)),
            SignInFormErrorPresentation.appleFailure
        )
        XCTAssertEqual(
            SignInFormErrorPresentation.inlineMessage(for: AuthenticationError.providerTokenInvalid(.apple)),
            SignInFormErrorPresentation.appleFailure
        )
    }

    func testCancelledIsSilent() {
        XCTAssertTrue(SignInFormErrorPresentation.inlineMessage(for: AuthenticationError.cancelled).isEmpty)
    }
}
