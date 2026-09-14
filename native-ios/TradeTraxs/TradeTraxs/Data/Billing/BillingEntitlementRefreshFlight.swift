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
