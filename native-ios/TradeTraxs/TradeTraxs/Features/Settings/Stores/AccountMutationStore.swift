import Foundation
import Observation

/// Broadcasts trading-account mutations so Dashboard / Calendar / Add Trade refresh without polling.
@Observable
@MainActor
final class AccountMutationStore {
    static let shared = AccountMutationStore()

    private(set) var revision: Int = 0
    private(set) var latestAccountID: TradingAccountID?

    private init() {}

    func noteAccountCreated(_ id: TradingAccountID) {
        latestAccountID = id
        revision += 1
    }

    func noteAccountUpdated(_ id: TradingAccountID) {
        latestAccountID = id
        revision += 1
    }

    func noteAccountsChanged() {
        revision += 1
    }

    func invalidate() {
        latestAccountID = nil
        revision = 0
    }
}
