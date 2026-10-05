import XCTest
@testable import TradeTraxs

final class SignupFailureDiagnosticsTests: XCTestCase {
    func testSupabaseAlreadyRegisteredBodyIsSafeAndSpecific() {
        let body = """
        {"code":422,"error_code":"user_already_exists","msg":"User already registered","email":"person@example.com"}
        """
        let report = SignupFailureDiagnostics.report(
            for: .transport(.validation(statusCode: 422, message: body))
        )

        XCTAssertEqual(report.httpStatus, 422)
        XCTAssertEqual(report.authErrorCode, "user_already_exists")
        XCTAssertEqual(report.message, "User already registered")
        XCTAssertTrue(report.bodyReceived)
        XCTAssertEqual(report.source, .supabase)
        XCTAssertFalse(report.logReason.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(report.logReason.contains("@"))
        XCTAssertFalse(report.logReason.localizedCaseInsensitiveContains("bearer"))
        XCTAssertFalse(report.logReason.localizedCaseInsensitiveContains("access_token"))
    }

    func testEmailInsideMessageIsRedacted() {
        let body = #"{"error_code":"email_exists","msg":"person@example.com is already registered"}"#
        let report = SignupFailureDiagnostics.report(
            for: .transport(.validation(statusCode: 422, message: body))
        )

        XCTAssertEqual(report.authErrorCode, "email_exists")
        XCTAssertEqual(report.message, "[redacted] is already registered")
        XCTAssertFalse(report.logReason.contains("@"))
    }

    func testPasswordOrTokenMessageIsOmitted() {
        let body = #"{"error_code":"weak_password","msg":"Password should be at least 6 characters"}"#
        let report = SignupFailureDiagnostics.report(
            for: .transport(.validation(statusCode: 422, message: body))
        )

        XCTAssertEqual(report.httpStatus, 422)
        XCTAssertEqual(report.authErrorCode, "weak_password")
        XCTAssertNil(report.message)
        XCTAssertTrue(report.bodyReceived)
        XCTAssertFalse(report.logReason.localizedCaseInsensitiveContains("at least"))
    }

    func testLocalTransportHasNoHTTPStatusOrBody() {
        let report = SignupFailureDiagnostics.report(for: .transport(.connectivity))

        XCTAssertNil(report.httpStatus)
        XCTAssertNil(report.authErrorCode)
        XCTAssertNil(report.message)
        XCTAssertFalse(report.bodyReceived)
        XCTAssertEqual(report.source, .localTransport)
    }

    func testEmptyValidationBodyIsNotTreatedAsReceived() {
        let report = SignupFailureDiagnostics.report(
            for: .transport(.validation(statusCode: 400, message: "Request failed"))
        )

        XCTAssertEqual(report.httpStatus, 400)
        XCTAssertEqual(report.source, .supabase)
        XCTAssertFalse(report.bodyReceived)
        XCTAssertNil(report.message)
    }
}
