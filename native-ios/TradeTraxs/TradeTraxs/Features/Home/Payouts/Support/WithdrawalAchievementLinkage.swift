import Foundation

/// Authoritative withdrawal ↔ achievement association stored in `achievements.metadata` (jsonb).
nonisolated enum WithdrawalAchievementLinkage {
    static let accountPayoutEntryIDKey = "account_payout_entry_id"
    static let accountPayoutCycleIDKey = "account_payout_cycle_id"

    enum Source: Hashable, Sendable {
        case ledgerEntry(AccountPayoutEntryID)
        case payoutCycle(String)
    }

    static func metadata(for source: Source?) -> JSONValue {
        guard let source else { return .object([:]) }
        switch source {
        case .ledgerEntry(let id):
            return .object([accountPayoutEntryIDKey: .string(id.rawValue)])
        case .payoutCycle(let cycleID):
            return .object([accountPayoutCycleIDKey: .string(cycleID)])
        }
    }

    static func source(from metadata: JSONValue?) -> Source? {
        guard case .object(let object) = metadata else { return nil }
        if case .string(let raw) = object[accountPayoutEntryIDKey],
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .ledgerEntry(AccountPayoutEntryID(raw))
        }
        if case .string(let raw) = object[accountPayoutCycleIDKey],
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .payoutCycle(raw)
        }
        return nil
    }

    static func source(for item: PayoutHistoryItem) -> Source? {
        if let entryID = item.ledgerEntryID {
            return .ledgerEntry(entryID)
        }
        if let cycleID = item.payoutCycleID {
            return .payoutCycle(cycleID)
        }
        return nil
    }

    static func matches(item: PayoutHistoryItem, source: Source) -> Bool {
        switch source {
        case .ledgerEntry(let id):
            return item.ledgerEntryID == id
        case .payoutCycle(let cycleID):
            return item.payoutCycleID == cycleID
        }
    }
}

nonisolated extension PayoutHistoryItem {
    var payoutCycleID: String? {
        guard id.hasPrefix("cycle:") else { return nil }
        return String(id.dropFirst("cycle:".count))
    }
}
