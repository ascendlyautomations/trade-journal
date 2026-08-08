import XCTest
@testable import TradeTraxs

final class NetworkingFoundationTests: XCTestCase {
    func testErrorMapperMapsHTTPStatuses() {
        let mapper = NetworkErrorMapper()
        let url = URL(string: "https://example.com")!

        XCTAssertEqual(
            mapper.map(data: nil, response: HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil), error: nil),
            .unauthorized
        )
        XCTAssertEqual(
            mapper.map(data: nil, response: HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil), error: nil),
            .forbidden
        )
        XCTAssertEqual(
            mapper.map(data: nil, response: HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "2"]), error: nil),
            .rateLimited(retryAfter: 2)
        )
        XCTAssertEqual(
            mapper.map(data: Data("boom".utf8), response: HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil), error: nil),
            .server(statusCode: 503, message: "boom")
        )
        XCTAssertNil(
            mapper.map(data: Data(), response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)
        )
    }

    func testErrorMapperMapsTransportConnectivity() {
        let mapper = NetworkErrorMapper()
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(mapper.mapTransport(error), .connectivity)
    }

    func testRetryPolicyIdempotentReadsOnly() {
        let policy = RetryPolicy.idempotentReads
        let get = makeRequest(method: .get, allowsRetry: true)
        let post = makeRequest(method: .post, allowsRetry: false)

        XCTAssertTrue(policy.shouldRetry(request: get, error: .timeout, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(request: get, error: .server(statusCode: 502, message: nil), attempt: 2))
        XCTAssertFalse(policy.shouldRetry(request: get, error: .unauthorized, attempt: 1))
        XCTAssertFalse(policy.shouldRetry(request: post, error: .timeout, attempt: 1))
        XCTAssertFalse(policy.shouldRetry(request: get, error: .timeout, attempt: 3))
    }

    func testRequestBuilderRequiresConfiguredBaseURL() {
        let configuration = NetworkConfiguration.make(
            environment: EnvironmentConfiguration(
                apiEnvironment: .debug,
                bffBaseURL: nil,
                supabaseURL: nil,
                supabaseAnonKey: nil,
                externalAPIBaseURL: nil,
                requestTimeout: 30,
                resourceTimeout: 300,
                httpMaximumConnectionsPerHost: 6,
                waitsForConnectivity: true
            )
        )
        let builder = RequestBuilder(configuration: configuration)
        let endpoint = Endpoint(host: .bff, path: "/api/health", method: .get, requiresAuthentication: false)

        XCTAssertThrowsError(try builder.makeRequest(endpoint: endpoint)) { error in
            guard let networkError = error as? NetworkError else {
                return XCTFail("Expected NetworkError")
            }
            XCTAssertEqual(networkError, .validation(message: "Base URL for bff is not configured"))
        }
    }

    func testRequestBuilderBuildsWhenBaseURLPresent() throws {
        let configuration = NetworkConfiguration.make(
            environment: EnvironmentConfiguration(
                apiEnvironment: .debug,
                bffBaseURL: URL(string: "https://www.tradetraxs.com"),
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabaseAnonKey: "anon-test-key",
                externalAPIBaseURL: nil,
                requestTimeout: 30,
                resourceTimeout: 300,
                httpMaximumConnectionsPerHost: 6,
                waitsForConnectivity: true
            )
        )
        let builder = RequestBuilder(configuration: configuration)
        let endpoint = Endpoint(host: .bff, path: "/api/health", method: .get, requiresAuthentication: false)
        let request = try builder.makeRequest(endpoint: endpoint)

        XCTAssertEqual(request.url.absoluteString, "https://www.tradetraxs.com/api/health")
        XCTAssertEqual(request.method, .get)
        XCTAssertTrue(request.allowsRetry)
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    @MainActor
    func testUserFacingErrorAndFeedbackBridge() {
        let offline = UserFacingError.map(NetworkError.connectivity)
        XCTAssertEqual(offline.title, "You're offline")
        XCTAssertEqual(offline.action, .retry)

        let feedback = FeedbackState.from(networkError: .connectivity)
        if case let .offline(message) = feedback {
            XCTAssertEqual(message, "Check your connection and try again.")
        } else {
            XCTFail("Expected offline feedback")
        }
    }

    func testAppErrorNetworkMapping() {
        XCTAssertEqual(AppError.network(.cancelled), .cancelled)
        XCTAssertEqual(AppError.network(.timeout), .transport(.timeout))
    }

    private func makeRequest(method: HTTPMethod, allowsRetry: Bool) -> HTTPRequest {
        HTTPRequest(
            endpoint: Endpoint(host: .bff, path: "/x", method: method, requiresAuthentication: false),
            url: URL(string: "https://example.com/x")!,
            method: method,
            headers: [:],
            body: nil,
            timeout: 30,
            idempotencyKey: nil,
            allowsRetry: allowsRetry
        )
    }
}
