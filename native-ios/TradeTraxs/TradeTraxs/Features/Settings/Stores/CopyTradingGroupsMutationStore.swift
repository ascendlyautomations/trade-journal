import Foundation
import Observation

/// Broadcasts copy-trading group create/update/delete so account filter menus stay current.
@Observable
@MainActor
final class CopyTradingGroupsMutationStore {
    static let shared = CopyTradingGroupsMutationStore()

    private(set) var revision: Int = 0
    private(set) var deletedGroupID: String?

    private init() {}

    func noteGroupsChanged(deletedGroupID: String? = nil) {
        self.deletedGroupID = deletedGroupID
        revision += 1
    }
}