import XCTest
@testable import TradeTraxs

final class GoogleOAuthFlowTests: XCTestCase {
    func testHttpsBridgeMatchesProductionContract() {
        let configuration = AppConfiguration.make(
            for: .production,
            secrets: SecretsLoader.Values(
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon",
                apiBaseURL: URL(string: "https://www.tradetraxs.com")
            )
        )
        XCTAssertEqual(
            NativeOAuthConfiguration.httpsBridgeURL(configuration: configuration).absoluteString,
            "https://www.tradetraxs.com/api/auth/native-callback"
        )
    }

    func testCallbackURLRecognition() throws {
        let callback = try XCTUnwrap(URL(string: "tradetraxs://auth/callback?code=abc123"))
        XCTAssertTrue(NativeOAuthConfiguration.isOAuthCallbackURL(callback))

        let legacyWrong = try XCTUnwrap(URL(string: "tradetraxs://auth-callback?code=abc123"))
        XCTAssertFalse(NativeOAuthConfiguration.isOAuthCallbackURL(legacyWrong))
    }

    func testFragmentOrQueryItemsMergePKCEAndImplicitFields() throws {
        let pkce = try XCTUnwrap(URL(string: "tradetraxs://auth/callback?code=abc&state=xyz"))
        let pkceValues = NativeOAuthConfiguration.fragmentOrQueryItems(from: pkce)
        XCTAssertEqual(pkceValues["code"], "abc")
        XCTAssertEqual(pkceValues["state"], "xyz")

        let implicit = try XCTUnwrap(
            URL(string: "tradetraxs://auth/callback#access_token=token123&refresh_token=refresh123&expires_in=3600")
        )
        let implicitValues = NativeOAuthConfiguration.fragmentOrQueryItems(from: implicit)
        XCTAssertEqual(implicitValues["access_token"], "token123")
        XCTAssertEqual(implicitValues["refresh_token"], "refresh123")
        XCTAssertEqual(implicitValues["expires_in"], "3600")
    }

    func testPKCEChallengeIsDeterministicForVerifier() {
        let verifier = "test-verifier-value"
        let challenge = NativeOAuthConfiguration.codeChallenge(for: verifier)
        XCTAssertFalse(challenge.isEmpty)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
        XCTAssertEqual(
            NativeOAuthConfiguration.codeChallenge(for: verifier),
            challenge
        )
    }

    func testOAuthBridgeResumesContinuationExactlyOnce() async throws {
        let bridge = OAuthWebAuthenticationSessionBridge()
        let callbackURL = try XCTUnwrap(URL(string: "tradetraxs://auth/callback?code=abc123"))

        let resolved = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            bridge.bind(continuation: continuation)
            XCTAssertTrue(bridge.finishOnce(with: .success(callbackURL), source: .callbackSuccess))
            XCTAssertFalse(
                bridge.finishOnce(with: .failure(AuthenticationError.cancelled), source: .userCancellation)
            )
            XCTAssertFalse(
                bridge.finishOnce(
                    with: .failure(AuthenticationError.providerUnavailable(.google)),
                    source: .sessionError
                )
            )
        }

        XCTAssertEqual(resolved, callbackURL)
    }

    func testOAuthBridgeFirstCompletionWinsOverLateCallback() async {
        let bridge = OAuthWebAuthenticationSessionBridge()
        let callbackURL = URL(string: "tradetraxs://auth/callback?code=late")!

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                bridge.bind(continuation: continuation)
                XCTAssertTrue(
                    bridge.finishOnce(with: .failure(AuthenticationError.cancelled), source: .userCancellation)
                )
                XCTAssertFalse(bridge.finishOnce(with: .success(callbackURL), source: .callbackSuccess))
            }
            XCTFail("Expected cancellation")
        } catch AuthenticationError.cancelled {
            // Expected — late success must not resume again.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOAuthBridgeStartFailureBlocksLaterCallback() async {
        let bridge = OAuthWebAuthenticationSessionBridge()
        let callbackURL = URL(string: "tradetraxs://auth/callback?code=abc")!

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                bridge.bind(continuation: continuation)
                XCTAssertTrue(
                    bridge.finishOnce(
                        with: .failure(AuthenticationError.providerUnavailable(.google)),
                        source: .startFailed
                    )
                )
                XCTAssertFalse(bridge.finishOnce(with: .success(callbackURL), source: .callbackSuccess))
            }
            XCTFail("Expected provider unavailable")
        } catch AuthenticationError.providerUnavailable(.google) {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
