import Foundation
import Observation

/// Broadcasts trading-account mutations so Dashboard / Calendar / Add Trade refresh without polling.
@Observable
@MainActor
final class AccountMutationStore {
    enum MutationKind: Equatable {
        case generic
        case payoutRecorded(TradingAccountID)
    }

    static let shared = AccountMutationStore()

    private(set) var revision: Int = 0
    private(set) var latestAccountID: TradingAccountID?
    private(set) var latestKind: MutationKind = .generic

    private init() {}

    func noteAccountCreated(_ id: TradingAccountID) {
        latestKind = .generic
        latestAccountID = id
        revision += 1
    }

    func noteAccountUpdated(_ id: TradingAccountID) {
        latestKind = .generic
        latestAccountID = id
        revision += 1
    }

    func noteAccountsChanged() {
        latestKind = .generic
        revision += 1
    }

    /// Funded prop payout closed one cycle and opened the next — Dashboard must reload cycle boundaries.
    func notePayoutRecorded(accountID: TradingAccountID) {
        latestKind = .payoutRecorded(accountID)
        latestAccountID = accountID
        revision += 1
    }

    func invalidate() {
        latestAccountID = nil
        latestKind = .generic
        revision = 0
    }
}
