import Foundation

/// Normalized outbound request used by ``NetworkClient``.
nonisolated struct HTTPRequest: Sendable {
    var endpoint: Endpoint
    var url: URL
    var method: HTTPMethod
    var headers: [String: String]
    var body: Data?
    var timeout: TimeInterval?
    /// Stable key for metrics / future in-flight coalescing.
    var idempotencyKey: String?
    var allowsRetry: Bool

    var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        if let timeout {
            request.timeoutInterval = timeout
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
