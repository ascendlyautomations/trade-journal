import Foundation

/// Decides whether / how a failed request may be retried.
nonisolated struct RetryPolicy: Sendable {
    var maximumAttempts: Int
    var backoff: any BackoffStrategy
    var retryableMethods: Set<HTTPMethod>
    var retryNetworkFailures: Bool
    var retryServerErrors: Bool
    var retryRateLimited: Bool

    /// Safe default: retries idempotent reads only.
    static let idempotentReads = RetryPolicy(
        maximumAttempts: 3,
        backoff: ExponentialBackoffStrategy.standard,
        retryableMethods: [.get, .head],
        retryNetworkFailures: true,
        retryServerErrors: true,
        retryRateLimited: true
    )

    static let none = RetryPolicy(
        maximumAttempts: 1,
        backoff: ConstantBackoffStrategy(interval: 0),
        retryableMethods: [],
        retryNetworkFailures: false,
        retryServerErrors: false,
        retryRateLimited: false
    )

    func shouldRetry(
        request: HTTPRequest,
        error: NetworkError,
        attempt: Int
    ) -> Bool {
        guard attempt < maximumAttempts else { return false }
        guard request.allowsRetry else { return false }
        guard retryableMethods.contains(request.method) else { return false }

        switch error {
        case .connectivity, .timeout:
            return retryNetworkFailures
        case .server(let code, _) where (500..<600).contains(code):
            return retryServerErrors
        case .rateLimited:
            return retryRateLimited
        default:
            return false
        }
    }

    func delay(forAttempt attempt: Int, error: NetworkError) -> TimeInterval {
        if case let .rateLimited(retryAfter) = error, let retryAfter {
            return retryAfter
        }
        return backoff.delay(forAttempt: attempt)
    }
}
