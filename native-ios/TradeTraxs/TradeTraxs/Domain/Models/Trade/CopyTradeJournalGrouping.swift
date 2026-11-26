import Foundation

/// One Trades list row, single journal trade or one copy-trade action (presentation only).
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

    var copyTradeOwnerDisplay: CopyTradeOwnerJournalDisplay? {
        switch self {
        case .single: return nil
        case .copyGroup(let group): return group.ownerDisplay
        }
    }

    var copyParticipatingAccountLines: [String]? {
        copyTradeOwnerDisplay?.visibleAccountLines
    }
}

nonisolated struct CopyTradeJournalGroup: Equatable, Sendable {
    var batchKey: String
    var representative: TradeOwnerJournalSummary
    var members: [TradeOwnerJournalSummary]
    var ownerDisplay: CopyTradeOwnerJournalDisplay
}

/// Groups owner journal rows for Trades list, mirrors web `groupTradesForTradesPageDisplay`.
nonisolated enum CopyTradeJournalGrouping {
    static func group(
        _ items: [TradeOwnerJournalSummary],
        accounts: [TradingAccount],
        copyGroups: [CopyTradingGroup] = []
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
            guard let display = CopyTradePresentation.ownerJournalDisplay(
                members: members,
                accounts: accounts,
                copyGroups: copyGroups
            ) else {
                out.append(.single(representative))
                continue
            }
            out.append(
                .copyGroup(
                    CopyTradeJournalGroup(
                        batchKey: batchKey,
                        representative: representative,
                        members: members,
                        ownerDisplay: display
                    )
                )
            )
        }
        return out
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
