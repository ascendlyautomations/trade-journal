import Foundation

/// Injects Supabase `apikey` (+ anon Authorization fallback) for Supabase hosts.
nonisolated struct SupabaseHeadersInterceptor: RequestInterceptor {
    private let anonKey: String?

    init(anonKey: String?) {
        self.anonKey = anonKey
    }

    func intercept(_ request: HTTPRequest) async throws -> HTTPRequest {
        guard let anonKey, !anonKey.isEmpty else { return request }
        switch request.endpoint.host {
        case .supabase, .supabaseStorage, .supabaseFunctions:
            break
        case .bff, .external:
            return request
        }

        var headers = request.headers
        headers["apikey"] = anonKey
        if headers["Authorization"] == nil {
            headers["Authorization"] = "Bearer \(anonKey)"
        }
        return HTTPRequest(
            endpoint: request.endpoint,
            url: request.url,
            method: request.method,
            headers: headers,
            body: request.body,
            timeout: request.timeout,
            idempotencyKey: request.idempotencyKey,
            allowsRetry: request.allowsRetry
        )
    }
}
