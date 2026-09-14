import Foundation
import Observation

/// Last-known TraxPro entitlement for the signed-in user — refreshed on foreground + Settings.
@Observable
@MainActor
final class SessionBillingEntitlementStore {
    static let shared = SessionBillingEntitlementStore()

    private(set) var status: BillingStatus?

    private init() {}

    func apply(_ status: BillingStatus) {
        self.status = status
    }

    func clear() {
        status = nil
    }
}

extension Notification.Name {
    static let billingEntitlementsDidRefresh = Notification.Name("billingEntitlementsDidRefresh")
}
