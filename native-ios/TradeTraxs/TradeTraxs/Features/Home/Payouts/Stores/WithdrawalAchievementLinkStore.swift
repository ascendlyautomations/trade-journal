import Foundation
import Observation

/// Maps withdrawal ledger rows / payout cycles → achievements (from metadata, one bulk fetch).
@Observable
@MainActor
final class WithdrawalAchievementLinkStore {
    static let shared = WithdrawalAchievementLinkStore()

    private var achievementByLedgerEntryID: [String: AchievementID] = [:]
    private var achievementByPayoutCycleID: [String: AchievementID] = [:]

    private init() {}

    func linkedAchievementID(for item: PayoutHistoryItem) -> AchievementID? {
        if let entryID = item.ledgerEntryID?.rawValue,
           let linked = achievementByLedgerEntryID[entryID]
        {
            return linked
        }
        if let cycleID = item.payoutCycleID,
           let linked = achievementByPayoutCycleID[cycleID]
        {
            return linked
        }
        return nil
    }

    func applyFetched(_ rows: [WithdrawalAchievementLinkRow]) {
        var byEntry: [String: AchievementID] = [:]
        var byCycle: [String: AchievementID] = [:]
        for row in rows {
            if let entryID = row.ledgerEntryID?.rawValue {
                byEntry[entryID] = row.achievementID
            }
            if let cycleID = row.payoutCycleID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cycleID.isEmpty
            {
                byCycle[cycleID] = row.achievementID
            }
        }
        achievementByLedgerEntryID = byEntry
        achievementByPayoutCycleID = byCycle
    }

    func register(achievementID: AchievementID, source: WithdrawalAchievementLinkage.Source) {
        switch source {
        case .ledgerEntry(let id):
            achievementByLedgerEntryID[id.rawValue] = achievementID
        case .payoutCycle(let cycleID):
            achievementByPayoutCycleID[cycleID] = achievementID
        }
    }

    func invalidate() {
        achievementByLedgerEntryID = [:]
        achievementByPayoutCycleID = [:]
    }
}

nonisolated struct WithdrawalAchievementLinkRow: Sendable {
    var achievementID: AchievementID
    var ledgerEntryID: AccountPayoutEntryID?
    var payoutCycleID: String?
}
