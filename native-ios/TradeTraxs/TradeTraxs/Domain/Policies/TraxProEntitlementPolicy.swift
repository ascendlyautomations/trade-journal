import Foundation

/// TraxPro access — mirrors web `lib/subscription.ts` `isProActive` using ``BillingStatus`` fields.
///
/// Used for informational Plan UI and must stay aligned with server-side Pro gates
/// (Trade AI, limits, etc.) without requiring an active Stripe lifecycle when
/// `profiles.is_pro` is already true.
nonisolated enum TraxProEntitlementPolicy {
    static func isProEntitled(_ status: BillingStatus, now: Date = Date()) -> Bool {
        if status.plan == .pro { return true }

        switch status.lifecycle {
        case .active, .trialing:
            return true
        default:
            break
        }

        if let trialEndsAt = status.trialEndsAt, trialEndsAt > now {
            return true
        }

        return status.isProEntitled
    }
}

extension BillingStatus {
    /// Authoritative TraxPro entitlement for native UI — not limited to Stripe lifecycle alone.
    var hasTraxProAccess: Bool {
        TraxProEntitlementPolicy.isProEntitled(self)
    }
}
