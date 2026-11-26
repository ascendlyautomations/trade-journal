import Foundation
import Observation

@Observable
@MainActor
final class FirstTradeDetailCoachmarkStore {
    static let shared = FirstTradeDetailCoachmarkStore()

    private(set) var pendingTradeID: TradeID?
    /// Second-step highlight for the Backtest toolbar control (after trade-detail step settles).
    private(set) var backtestCoachmarkActive = false
    /// Trades journal chrome is ready to measure the Backtest toolbar.
    private(set) var tradesJournalReadyForBacktestCoachmark = false

    private var viewerID: ProfileID?
    private var stagedOwnerProfileID: ProfileID?
    private weak var navigationCoordinator: NavigationCoordinator?

    private init() {}

    func configure(viewerID: ProfileID?, navigationCoordinator: NavigationCoordinator) {
        self.viewerID = viewerID
        self.navigationCoordinator = navigationCoordinator
    }

    /// After a successful manual Add Trade create (Global Upload), when this was the owner's first trade.
    func stageAfterManualCreate(trade: Trade, priorPersistedTradeCount: Int) {
        guard priorPersistedTradeCount == 0 else { return }
        let owner = trade.ownerProfileID
        if let viewerID, viewerID != owner { return }
        guard !FirstTradeDetailCoachmarkPersistence.hasSeen(viewerID: owner) else { return }
        guard pendingTradeID == nil, !backtestCoachmarkActive else { return }

        stagedOwnerProfileID = owner
        pendingTradeID = trade.id
        backtestCoachmarkActive = false
        tradesJournalReadyForBacktestCoachmark = false
        navigationCoordinator?.presentOwnerTradesJournalRoot(source: "firstTradeDetailCoachmark")
    }

    func dismissGotIt() {
        if pendingTradeID != nil {
            advanceToBacktestCoachmarkIfEligible()
            return
        }
        if backtestCoachmarkActive {
            markSeenAndClearPending()
        }
    }

    /// User tapped the highlighted journal card; proceed to the Backtest highlight when eligible.
    func completeIfOpeningTrade(_ tradeID: TradeID) {
        guard pendingTradeID == tradeID else { return }
        advanceToBacktestCoachmarkIfEligible()
    }

    func noteTradesJournalReadyForBacktestCoachmark() {
        tradesJournalReadyForBacktestCoachmark = true
    }

    func resetTradesJournalReadyForBacktestCoachmark() {
        tradesJournalReadyForBacktestCoachmark = false
    }

    func resetForSessionBoundary() {
        pendingTradeID = nil
        backtestCoachmarkActive = false
        tradesJournalReadyForBacktestCoachmark = false
        stagedOwnerProfileID = nil
        viewerID = nil
        navigationCoordinator = nil
    }

    var isActive: Bool {
        pendingTradeID != nil || backtestCoachmarkActive
    }

    private func advanceToBacktestCoachmarkIfEligible() {
        pendingTradeID = nil
        let profileID = viewerID ?? stagedOwnerProfileID
        if let profileID, ProAccessGate.shouldPresentPaywall(profileID: profileID) {
            markSeenAndClearPending()
            return
        }
        backtestCoachmarkActive = true
        tradesJournalReadyForBacktestCoachmark = false
    }

    private func markSeenAndClearPending() {
        if let profileID = viewerID ?? stagedOwnerProfileID {
            FirstTradeDetailCoachmarkPersistence.markSeen(viewerID: profileID)
        }
        pendingTradeID = nil
        backtestCoachmarkActive = false
        tradesJournalReadyForBacktestCoachmark = false
        stagedOwnerProfileID = nil
    }
}