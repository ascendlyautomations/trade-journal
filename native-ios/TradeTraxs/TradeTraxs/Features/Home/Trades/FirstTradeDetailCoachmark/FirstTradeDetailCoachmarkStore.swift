import Foundation
import Observation

@Observable
@MainActor
final class FirstTradeDetailCoachmarkStore {
    static let shared = FirstTradeDetailCoachmarkStore()

    private(set) var pendingTradeID: TradeID?
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
        guard pendingTradeID == nil else { return }

        stagedOwnerProfileID = owner
        pendingTradeID = trade.id
        navigationCoordinator?.presentOwnerTradesJournalRoot(source: "firstTradeDetailCoachmark")
    }

    func dismissGotIt() {
        markSeenAndClearPending()
    }

    /// User tapped the highlighted journal card — allow normal detail navigation.
    func completeIfOpeningTrade(_ tradeID: TradeID) {
        guard pendingTradeID == tradeID else { return }
        markSeenAndClearPending()
    }

    func resetForSessionBoundary() {
        pendingTradeID = nil
        stagedOwnerProfileID = nil
        viewerID = nil
        navigationCoordinator = nil
    }

    private func markSeenAndClearPending() {
        if let profileID = viewerID ?? stagedOwnerProfileID {
            FirstTradeDetailCoachmarkPersistence.markSeen(viewerID: profileID)
        }
        pendingTradeID = nil
        stagedOwnerProfileID = nil
    }
}
