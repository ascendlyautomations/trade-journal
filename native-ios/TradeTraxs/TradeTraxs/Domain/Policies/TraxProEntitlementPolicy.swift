import Foundation

/// TraxPro access — delegates to ``TraxProEntitlementResolver`` (web `isTraxProActive`).
nonisolated enum TraxProEntitlementPolicy {
    static func isProEntitled(_ status: BillingStatus, now: Date = Date()) -> Bool {
        TraxProEntitlementResolver.resolve(status, now: now).isActive
    }
}

extension BillingStatus {
    /// Authoritative TraxPro entitlement for native UI and feature gates.
    var hasTraxProAccess: Bool {
        TraxProEntitlementResolver.resolve(self).isActive
    }
}
