import Foundation

/// URLSession for **public** Supabase Storage GETs — honors HTTP/CDN cache headers.
nonisolated enum MediaURLSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 32 * 1_024 * 1_024,
            diskPath: "TradeTraxsMediaHTTP"
        )
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
}
