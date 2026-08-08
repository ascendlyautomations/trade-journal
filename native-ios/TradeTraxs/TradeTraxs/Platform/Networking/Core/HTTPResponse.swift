import Foundation

/// Normalized inbound response.
nonisolated struct HTTPResponse: Sendable {
    let data: Data
    let httpURLResponse: HTTPURLResponse
    let metrics: RequestMetrics?

    var statusCode: Int { httpURLResponse.statusCode }
    var headers: [AnyHashable: Any] { httpURLResponse.allHeaderFields }

    var isSuccessful: Bool { (200..<300).contains(statusCode) }
}
