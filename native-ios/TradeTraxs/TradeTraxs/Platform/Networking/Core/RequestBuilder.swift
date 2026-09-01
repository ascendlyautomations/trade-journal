import Foundation

/// Builds ``HTTPRequest`` values from endpoints + environment hosts.
nonisolated struct RequestBuilder: Sendable {
    let configuration: NetworkConfiguration

    func makeRequest(
        endpoint: Endpoint,
        body: Data? = nil,
        additionalHeaders: [String: String] = [:],
        timeout: TimeInterval? = nil,
        idempotencyKey: String? = nil
    ) throws -> HTTPRequest {
        let baseURL = try baseURL(for: endpoint.host)
        // Preserve multi-segment paths (PostgREST / GoTrue / Storage). Do not use
        // `appendingPathComponent`, which percent-encodes `/`.
        var base = baseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        let path = endpoint.path.hasPrefix("/") ? endpoint.path : "/\(endpoint.path)"
        guard var components = URLComponents(string: base + path) else {
            throw NetworkError.validation(statusCode: nil, message: "Invalid URL components for \(endpoint.path)")
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        guard let url = components.url else {
            throw NetworkError.validation(statusCode: nil, message: "Unable to form URL for \(endpoint.path)")
        }

        var headers = configuration.defaultHeaders
            .merging(endpoint.headers) { _, new in new }
            .merging(additionalHeaders) { _, new in new }

        if body != nil, headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }

        return HTTPRequest(
            endpoint: endpoint,
            url: url,
            method: endpoint.method,
            headers: headers,
            body: body,
            timeout: timeout ?? configuration.environment.requestTimeout,
            idempotencyKey: idempotencyKey,
            allowsRetry: endpoint.isIdempotent
        )
    }

    private func baseURL(for host: APIHost) throws -> URL {
        let environment = configuration.environment
        let url: URL?
        switch host {
        case .bff:
            url = Self.canonicalBFFURL(environment.bffBaseURL)
        case .supabase, .supabaseStorage, .supabaseFunctions:
            url = environment.supabaseURL
        case .external:
            url = environment.externalAPIBaseURL
        }

        guard let url else {
            throw NetworkError.validation(
                statusCode: nil,
                message: "Base URL for \(host.rawValue) is not configured"
            )
        }
        return url
    }

    /// Apex `tradetraxs.com` → `www` so URLSession does not 308-redirect and strip `Authorization`.
    private static func canonicalBFFURL(_ url: URL?) -> URL? {
        guard var url else { return nil }
        guard let host = url.host?.lowercased() else { return url }
        if host == "tradetraxs.com" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = "www.tradetraxs.com"
            if let canonical = components?.url {
                url = canonical
            }
        }
        return url
    }
}
