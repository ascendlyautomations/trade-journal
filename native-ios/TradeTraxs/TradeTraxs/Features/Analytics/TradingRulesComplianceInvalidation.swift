import Foundation

extension Notification.Name {
    static let tradingRulesComplianceOwnerTradesChanged = Notification.Name(
        "tradingRulesComplianceOwnerTradesChanged"
    )
}

/// Invalidates compliance caches when owner trade rows change outside a full dashboard recompute.
enum TradingRulesComplianceInvalidation {
    static func ownerTradesDidMutate(profileID: ProfileID) {
        TradingRulesComplianceRecomputeCoordinator.reset()
        NotificationCenter.default.post(
            name: .tradingRulesComplianceOwnerTradesChanged,
            object: nil,
            userInfo: ["profileID": profileID.rawValue]
        )
    }
}
