import Foundation

/// Single-flight foreground entitlement refresh — avoids duplicate billing RPCs.
actor BillingEntitlementRefreshFlight {
    static let shared = BillingEntitlementRefreshFlight()

    private var inFlight: Task<Void, Never>?

    func refresh(_ operation: @Sendable @escaping () async -> Void) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task {
            await operation()
        }
        inFlight = task
        defer { inFlight = nil }
        await task.value
    }
}

/// Coalesces overlapping monetization-config fetches for the same user.
actor MonetizationConfigRefreshFlight {
    static let shared = MonetizationConfigRefreshFlight()

    private var inFlight: [String: Task<Bool, Never>] = [:]
    private var lastSuccessAt: [String: Date] = [:]
    /// Drops a second fetch that starts immediately after a successful one.
    private let dedupeInterval: TimeInterval = 2

    func run(
        userID: String,
        operation: @Sendable @escaping () async -> Bool
    ) async {
        if let existing = inFlight[userID] {
            _ = await existing.value
            return
        }
        if let lastSuccessAt = lastSuccessAt[userID],
           Date().timeIntervalSince(lastSuccessAt) < dedupeInterval {
            return
        }
        let task = Task { await operation() }
        inFlight[userID] = task
        let succeeded = await task.value
        inFlight[userID] = nil
        if succeeded {
            self.lastSuccessAt[userID] = Date()
        }
    }
}
