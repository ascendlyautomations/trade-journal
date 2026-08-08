import Foundation

/// Session-level networking configuration.
nonisolated struct NetworkConfiguration: Sendable {
    let environment: EnvironmentConfiguration
    let userAgent: String
    let defaultHeaders: [String: String]
    let retryPolicy: RetryPolicy
    let enablesMetricCollection: Bool

    static func make(
        environment: EnvironmentConfiguration,
        appDisplayName: String = "TradeTraxs"
    ) -> NetworkConfiguration {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return NetworkConfiguration(
            environment: environment,
            userAgent: "\(appDisplayName)/\(version) (\(build); iOS)",
            defaultHeaders: [
                "Accept": "application/json",
                "Accept-Language": Locale.current.identifier,
            ],
            retryPolicy: .idempotentReads,
            enablesMetricCollection: true
        )
    }

    func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = environment.requestTimeout
        configuration.timeoutIntervalForResource = environment.resourceTimeout
        configuration.httpMaximumConnectionsPerHost = environment.httpMaximumConnectionsPerHost
        configuration.waitsForConnectivity = environment.waitsForConnectivity
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = defaultHeaders.merging(
            ["User-Agent": userAgent]
        ) { _, new in new }
        return configuration
    }

    func makeBackgroundURLSessionConfiguration(identifier: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForResource = environment.resourceTimeout
        configuration.httpAdditionalHeaders = defaultHeaders.merging(
            ["User-Agent": userAgent]
        ) { _, new in new }
        return configuration
    }
}
