import Foundation

/// One Trades list row — single journal trade or one copy-trade action (presentation only).
nonisolated enum TradeHistoryDisplayItem: Equatable, Sendable, Identifiable {
    case single(TradeOwnerJournalSummary)
    case copyGroup(CopyTradeJournalGroup)

    var id: TradeID { representative.id }

    var representative: TradeOwnerJournalSummary {
        switch self {
        case .single(let item): return item
        case .copyGroup(let group): return group.representative
        }
    }

    var copyParticipatingAccountLines: [String]? {
        switch self {
        case .single: return nil
        case .copyGroup(let group): return group.participatingAccountLines
        }
    }
}

nonisolated struct CopyTradeJournalGroup: Equatable, Sendable {
    var batchKey: String
    var representative: TradeOwnerJournalSummary
    var members: [TradeOwnerJournalSummary]
    var participatingAccountLines: [String]
}

/// Groups owner journal rows for Trades list — mirrors web `groupTradesForTradesPageDisplay`.
nonisolated enum CopyTradeJournalGrouping {
    static func group(
        _ items: [TradeOwnerJournalSummary],
        accounts: [TradingAccount]
    ) -> [TradeHistoryDisplayItem] {
        let batchIndex = indexBatchMembers(items)
        var consumed = Set<String>()
        var out: [TradeHistoryDisplayItem] = []

        for item in items {
            guard let batchKey = CopyTradePresentation.batchKey(for: item) else {
                out.append(.single(item))
                continue
            }
            if consumed.contains(batchKey) { continue }
            consumed.insert(batchKey)
            let members = batchIndex[batchKey] ?? [item]
            #if DEBUG
            ProfileCopySummaryDiagnostics.logSiblingsBeforeCollapse(members)
            #endif
            let representative = pickRepresentative(from: members)
            let lines = participatingAccountLines(members: members, accounts: accounts)
            out.append(
                .copyGroup(
                    CopyTradeJournalGroup(
                        batchKey: batchKey,
                        representative: representative,
                        members: members,
                        participatingAccountLines: lines
                    )
                )
            )
        }
        return out
    }

    static func participatingAccountLines(
        members: [TradeOwnerJournalSummary],
        accounts: [TradingAccount]
    ) -> [String] {
        let orderedIDs = CopyTradePresentation.participatingAccountIDsForCopyGroup(members)

        return orderedIDs.map { accountID in
            let member = members.first { $0.accountID == accountID }
            return CopyTradePresentation.ownerJournalAccountLine(
                accountID: accountID,
                member: member,
                accounts: accounts
            )
        }
    }

    private static func indexBatchMembers(
        _ items: [TradeOwnerJournalSummary]
    ) -> [String: [TradeOwnerJournalSummary]] {
        var map: [String: [TradeOwnerJournalSummary]] = [:]
        for item in items {
            guard let key = CopyTradePresentation.batchKey(for: item) else { continue }
            map[key, default: []].append(item)
        }
        return map
    }

    private static func pickRepresentative(
        from members: [TradeOwnerJournalSummary]
    ) -> TradeOwnerJournalSummary {
        if let source = members.first(where: { member in
            guard let metadata = member.copyTrade,
                  let sourceID = metadata.sourceAccountID,
                  let rowID = member.accountID
            else { return false }
            return sourceID == rowID
        }) {
            return source
        }
        return members[0]
    }
}
