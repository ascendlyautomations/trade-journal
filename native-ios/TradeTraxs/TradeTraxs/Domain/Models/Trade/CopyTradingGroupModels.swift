import Foundation

/// Shared copy-trading group. Same rows as web `copy_trading_groups` + `copy_trading_group_accounts`.
nonisolated struct CopyTradingGroup: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
    /// Account ids in `sort_order`. The first id is the source account when journaling.
    var accountIDs: [String]
    var createdAt: String
    var updatedAt: String
}

/// One owned account stamped onto a copied journal row.
nonisolated struct CopyTradingAccountStamp: Hashable, Codable, Sendable {
    var accountID: TradingAccountID
    var name: String
    var sizeLabel: String?
    var modeLabel: String
    var categoryLabel: String?
    var accountNumber: String?
    var category: TradingAccountCategory?
    var mode: TradingAccountMode?
}

/// Create-time plan. Edit saves omit this so the existing group link on the row stays put.
nonisolated struct CopyTradingSavePlan: Hashable, Codable, Sendable {
    var groupID: String
    /// Membership order. Index 0 is the source account; the rest are `copied_account_ids`.
    var accounts: [CopyTradingAccountStamp]
}

enum CopyTradingGroupRules {
    static let minimumAccounts = 2

    /// Native create/update requires two owned accounts. Web's database still accepts one;
    /// this is the product rule for a copy group.
    static func validationError(
        name: String,
        accountIDs: [String],
        ownedAccountIDs: Set<String>
    ) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Group name is required"
        }
        var ordered: [String] = []
        var seen = Set<String>()
        for id in accountIDs {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        if ordered.contains(where: { !ownedAccountIDs.contains($0) }) {
            return "You can only add accounts you own."
        }
        if ordered.count < minimumAccounts {
            return "Select at least two accounts."
        }
        return nil
    }
}

/// Journal rows for one copy-group submission. One row per linked account, same P&L, no extra summary row.
nonisolated enum CopyTradingTradeFanout {
    nonisolated struct Row: Equatable, Sendable {
        var accountID: String
        var tradeMode: String
        var sourceAccountID: String
        var copiedAccountIDs: [String]
        var groupID: String
        var pnl: Decimal
    }

    static func rows(groupID: String, orderedAccountIDs: [String], pnl: Decimal) -> [Row] {
        let ids = orderedAccountIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let source = ids.first else { return [] }
        let copied = Array(ids.dropFirst())
        return ids.map { accountID in
            Row(
                accountID: accountID,
                tradeMode: "copy_traded",
                sourceAccountID: source,
                copiedAccountIDs: copied,
                groupID: groupID,
                pnl: pnl
            )
        }
    }
}

/// Deleting a group dissolves membership only.
enum CopyTradingGroupDeletionEffect {
    static let removesTradingAccounts = false
    static let removesTrades = false
    static let removesBrokerConnections = false
    static let unlinksCopyTradingGroupID = true
}
