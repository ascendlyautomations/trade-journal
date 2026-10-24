import Foundation
import Observation

/// In-memory owner labels so the expense tracker sees a firm saved from a payout detail.
@MainActor
@Observable
final class PropFirmPayoutAssignmentStore {
    static let shared = PropFirmPayoutAssignmentStore()

    private(set) var namesByKey: [String: String] = [:]

    func replace(_ names: [String: String]) {
        namesByKey = names
    }

    func set(name: String?, for payoutKey: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            namesByKey.removeValue(forKey: payoutKey)
        } else {
            namesByKey[payoutKey] = trimmed
        }
    }
}
