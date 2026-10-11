import XCTest
@testable import TradeTraxs

final class SocialSignInAppleCompletionRoutingTests: XCTestCase {
    /// Regression: LoginView sets `isOAuthInteractionInFlight`, which disables social buttons (`isEnabled == false`).
    /// Completion must still deliver the credential from an authorization that already started.
    func testDeliversCredentialWhileOAuthInteractionInFlightWouldDisableButtons() {
        let route = SocialSignInAppleCompletionRouting.routeSuccessfulAuthorization(
            idToken: "id-token",
            rawNonce: "raw-nonce",
            authorizationCode: "auth-code",
            fullName: "Alex Morgan",
            email: "alex@privaterelay.appleid.com",
            credentialAlreadyDelivered: false
        )

        guard case .deliver(let payload) = route else {
            return XCTFail("Expected deliver, got \(route)")
        }
        XCTAssertEqual(payload.idToken, "id-token")
        XCTAssertEqual(payload.nonce, "raw-nonce")
        XCTAssertEqual(payload.authorizationCode, "auth-code")
        XCTAssertEqual(payload.fullName, "Alex Morgan")
        XCTAssertEqual(payload.email, "alex@privaterelay.appleid.com")
    }

    func testIgnoresDuplicateDeliveryForSameAuthorization() {
        let route = SocialSignInAppleCompletionRouting.routeSuccessfulAuthorization(
            idToken: "id-token",
            rawNonce: "raw-nonce",
            authorizationCode: nil,
            fullName: nil,
            email: nil,
            credentialAlreadyDelivered: true
        )
        XCTAssertEqual(route, .duplicateDelivery)
    }
}
