import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"

    var isIdempotent: Bool {
        switch self {
        case .get, .head, .put, .delete:
            return true
        case .post, .patch:
            return false
        }
    }
}
