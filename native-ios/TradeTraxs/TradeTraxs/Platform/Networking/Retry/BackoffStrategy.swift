import Foundation

/// Computes delay before a retry attempt.
nonisolated protocol BackoffStrategy: Sendable {
    func delay(forAttempt attempt: Int) -> TimeInterval
}

nonisolated struct ExponentialBackoffStrategy: BackoffStrategy {
    var base: TimeInterval
    var multiplier: Double
    var jitter: TimeInterval
    var maximum: TimeInterval

    static let standard = ExponentialBackoffStrategy(
        base: 0.35,
        multiplier: 2,
        jitter: 0.15,
        maximum: 8
    )

    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exp = base * pow(multiplier, Double(max(0, attempt - 1)))
        let jitterValue = Double.random(in: 0...jitter)
        return min(maximum, exp + jitterValue)
    }
}

nonisolated struct ConstantBackoffStrategy: BackoffStrategy {
    var interval: TimeInterval

    func delay(forAttempt attempt: Int) -> TimeInterval {
        _ = attempt
        return interval
    }
}
