import Foundation

/// User-facing subscription copy derived from unified entitlement — no external checkout URLs.
nonisolated enum SubscriptionPresentationPolicy {
    static func activeSummary(for status: BillingStatus) -> String {
        switch status.entitlementSource {
        case .apple:
            return "Your TraxPro subscription is active through the App Store."
        case .stripe:
            return "Your TraxPro subscription is active. Billing is managed outside the App Store."
        case .creator, .earlyAccess, .manual:
            return "Your account has access to TraxPro features."
        case .none:
            return status.hasTraxProAccess
                ? "Your account has access to TraxPro features."
                : "Your account is currently on the Free plan."
        }
    }

    static func billingDetail(for status: BillingStatus) -> String? {
        switch status.entitlementSource {
        case .apple:
            if let interval = status.billingInterval?.displayLabel {
                return "Plan: \(interval)"
            }
            if let productID = status.appleProductID {
                return "Plan: \(productID)"
            }
            return nil
        case .stripe:
            if let interval = status.billingInterval?.displayLabel {
                return "Plan: \(interval)"
            }
            if status.lifecycle == .trialing {
                return "Trial active"
            }
            return "Active membership"
        case .creator:
            return "Creator access"
        case .earlyAccess:
            return "Early access"
        case .manual:
            return "Granted access"
        case .none:
            return nil
        }
    }

    static func renewalDetail(for status: BillingStatus, now: Date = Date()) -> String? {
        switch status.entitlementSource {
        case .apple:
            if let expires = status.appleExpiresAt {
                return expires > now ? "Renews \(Self.format(date: expires))" : "Expired \(Self.format(date: expires))"
            }
            return nil
        case .stripe:
            if status.cancelAtPeriodEnd, let end = status.currentPeriodEndsAt {
                return "Access until \(Self.format(date: end))"
            }
            if let end = status.currentPeriodEndsAt {
                return "Renews \(Self.format(date: end))"
            }
            if let trial = status.trialEndsAt, trial > now {
                return "Trial ends \(Self.format(date: trial))"
            }
            return nil
        case .earlyAccess:
            if let end = status.earlyAccessEndsAt, end > now {
                return "Access until \(Self.format(date: end))"
            }
            return nil
        default:
            return nil
        }
    }

    static func showsApplePurchaseOptions(for status: BillingStatus?) -> Bool {
        guard let status else { return false }
        return !status.hasTraxProAccess
    }

    static func showsAppleManageSubscription(for status: BillingStatus?) -> Bool {
        status?.entitlementSource == .apple && status?.hasTraxProAccess == true
    }

    static func autoRenewDisclosure(selectedProduct: StoreKitTraxProProduct?) -> String {
        guard let selectedProduct else {
            return "Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period."
        }
        return "\(selectedProduct.displayName) (\(selectedProduct.displayPrice) / \(selectedProduct.subscriptionPeriodLabel)) auto-renews until cancelled in your Apple ID Subscriptions."
    }

    private static func format(date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension BillingInterval {
    var displayLabel: String {
        switch self {
        case .monthly: return "Monthly"
        case .sixMonth: return "6 Months"
        case .yearly: return "Yearly"
        }
    }
}
