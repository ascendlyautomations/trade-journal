import Foundation

/// Logical backend host family. Concrete paths are supplied later by services.
nonisolated enum APIHost: String, Sendable {
    case bff
    case supabase
    case supabaseStorage
    case supabaseFunctions
    case external
}

/// Declarative endpoint description — not an implemented feature call.
nonisolated struct Endpoint: Sendable, Hashable {
    var host: APIHost
    var path: String
    var method: HTTPMethod
    var queryItems: [URLQueryItem]
    var headers: [String: String]
    var requiresAuthentication: Bool
    var isIdempotent: Bool

    init(
        host: APIHost,
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        requiresAuthentication: Bool = true,
        isIdempotent: Bool? = nil
    ) {
        self.host = host
        self.path = path.hasPrefix("/") ? path : "/\(path)"
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.requiresAuthentication = requiresAuthentication
        self.isIdempotent = isIdempotent ?? method.isIdempotent
    }
}
