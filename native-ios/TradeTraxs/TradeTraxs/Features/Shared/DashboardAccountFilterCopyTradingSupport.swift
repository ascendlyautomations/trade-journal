import Foundation

/// Copy-trading account filter keys, titles, and trade matching (mirrors web `tradeAccountSelection.ts`).
nonisolated enum DashboardAccountFilterCopyTradingSupport {
    static let copyGroupFilterPrefix = "copygroup:"
    static let copyTradingAllFilterKey = "copy-trading-all"

    static func copyGroupFilterValue(groupID: String) -> String {
        "\(copyGroupFilterPrefix)\(groupID)"
    }

    static func parseCopyGroupFilterValue(_ value: String) -> String? {
        guard value.hasPrefix(copyGroupFilterPrefix) else { return nil }
        let id = String(value.dropFirst(copyGroupFilterPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    static func isCopyGroupFilterKey(_ value: String) -> Bool {
        parseCopyGroupFilterValue(value) != nil
    }

    static func linkedAccountIDs(from groups: [CopyTradingGroup]) -> Set<String> {
        var ids = Set<String>()
        for group in groups {
            for raw in group.accountIDs {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { ids.insert(trimmed) }
            }
        }
        return ids
    }

    static func accountIDs(forGroupID groupID: String, groups: [CopyTradingGroup]) -> Set<String> {
        guard let group = groups.first(where: { $0.id == groupID }) else { return [] }
        return Set(
            group.accountIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    /// Owner account picker — copy-linked accounts appear only under Copy Trading groups.
    static func standaloneMenuAccounts(
        from accounts: [TradingAccount],
        copyGroups: [CopyTradingGroup],
        preservingSelection selectedID: TradingAccountID?
    ) -> [TradingAccount] {
        let linked = linkedAccountIDs(from: copyGroups)
        guard !linked.isEmpty else {
            return accounts.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        var visible = accounts.filter { !linked.contains($0.id.rawValue) }
        if let selectedID,
           linked.contains(selectedID.rawValue),
           let selected = accounts.first(where: { $0.id == selectedID }) {
            visible.append(selected)
        }
        return visible.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func copyLinkedAccounts(
        accounts: [TradingAccount],
        groups: [CopyTradingGroup]
    ) -> [TradingAccount] {
        let linked = linkedAccountIDs(from: groups)
        guard !linked.isEmpty else { return [] }
        return accounts.filter { linked.contains($0.id.rawValue) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func sanitizedFilter(
        _ filter: DashboardAccountFilter,
        accounts: [TradingAccount],
        copyGroups: [CopyTradingGroup]
    ) -> DashboardAccountFilter {
        switch filter {
        case .all:
            return filter
        case .copyTradingAll:
            return copyGroups.isEmpty ? .all : filter
        case .account(let id):
            let scoped = DashboardAccountScopePolicy.sanitizedFilter(filter, accounts: accounts)
            guard scoped == filter else { return scoped }
            let linked = linkedAccountIDs(from: copyGroups)
            guard linked.contains(id.rawValue) else { return scoped }
            let groups = copyGroups.filter { group in
                group.accountIDs.contains(id.rawValue)
            }
            if groups.count == 1, let only = groups.first {
                return .copyTradingGroup(only.id)
            }
            return copyGroups.isEmpty ? .all : .copyTradingAll
        case .copyTradingGroup(let groupID):
            let trimmed = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  copyGroups.contains(where: { $0.id == trimmed })
            else { return .all }
            return .copyTradingGroup(trimmed)
        }
    }

    static func persistenceKey(for filter: DashboardAccountFilter) -> String {
        switch filter {
        case .all:
            return "all"
        case .account(let id):
            if JournalSampleDataPolicy.isCanonicalAccount(id: id) { return "all" }
            if UUID(uuidString: id.rawValue) == nil { return "all" }
            return id.rawValue
        case .copyTradingAll:
            return copyTradingAllFilterKey
        case .copyTradingGroup(let groupID):
            return copyGroupFilterValue(groupID: groupID)
        }
    }

    static func filter(fromPersistenceKey key: String?) -> DashboardAccountFilter {
        guard let key, key != "all", !key.isEmpty else { return .all }
        if key == copyTradingAllFilterKey { return .copyTradingAll }
        if let groupID = parseCopyGroupFilterValue(key) {
            return .copyTradingGroup(groupID)
        }
        let accountID = TradingAccountID(key)
        if JournalSampleDataPolicy.isCanonicalAccount(id: accountID) { return .all }
        if UUID(uuidString: key) == nil { return .all }
        return .account(accountID)
    }

    static func menuTitle(
        for filter: DashboardAccountFilter,
        accounts: [TradingAccount],
        copyGroups: [CopyTradingGroup]
    ) -> String {
        switch filter {
        case .all:
            return "All Accounts"
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
            }
            return "Account"
        case .copyTradingAll:
            return "All Copy Trading Accounts"
        case .copyTradingGroup(let groupID):
            if let group = copyGroups.first(where: { $0.id == groupID }) {
                return "Copy · \(group.name)"
            }
            return "Copy Trading Group"
        }
    }

    static func matchesTrade(
        _ trade: Trade,
        filter: DashboardAccountFilter,
        copyGroups: [CopyTradingGroup]
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .account(let id):
            return CopyTradePresentation.matchesParticipatingAccountFilter(trade: trade, accountID: id)
        case .copyTradingAll:
            let linked = linkedAccountIDs(from: copyGroups)
            guard !linked.isEmpty else { return false }
            return tradeMatchesLinkedCopyAccounts(trade, linkedAccountIDs: linked)
        case .copyTradingGroup(let groupID):
            let accountIDs = accountIDs(forGroupID: groupID, groups: copyGroups)
            guard !accountIDs.isEmpty else { return false }
            return tradeMatchesLinkedCopyAccounts(trade, linkedAccountIDs: accountIDs)
        }
    }

  private static func tradeMatchesLinkedCopyAccounts(
        _ trade: Trade,
        linkedAccountIDs: Set<String>
    ) -> Bool {
        if let rowID = trade.accountID?.rawValue, linkedAccountIDs.contains(rowID) {
            return true
        }
        guard trade.mode == .copyTraded, let metadata = trade.copyTrade else {
            return false
        }
        let participating = CopyTradePresentation.participatingAccountIDs(
            metadata: metadata,
            rowAccountID: trade.accountID
        )
        return participating.contains { linkedAccountIDs.contains($0.rawValue) }
    }

    /// One journal row per copy action for KPI math (avoids multiplying P&L across sibling rows).
    static func dedupeCopyTradedTradesForMetrics(_ trades: [Trade]) -> [Trade] {
        var seenBatches = Set<String>()
        var output: [Trade] = []
        for trade in trades {
            if trade.mode == .copyTraded,
               let key = CopyTradePresentation.batchKey(for: trade)
            {
                guard seenBatches.insert(key).inserted else { continue }
            }
            output.append(trade)
        }
        return output
    }

    static func shouldDedupeCopyMetrics(for filter: DashboardAccountFilter) -> Bool {
        switch filter {
        case .copyTradingAll, .copyTradingGroup:
            return true
        case .all, .account:
            return false
        }
    }
}