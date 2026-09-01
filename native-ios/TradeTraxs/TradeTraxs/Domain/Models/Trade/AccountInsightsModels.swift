import Foundation

/// Owner-managed manual payout row (`account_payout_entries`).
nonisolated struct AccountPayoutEntry: Hashable, Codable, Sendable, Identifiable {
    var id: AccountPayoutEntryID
    var accountID: TradingAccountID
    var amount: Money
    var payoutDate: Date
    var note: String?
}

nonisolated struct AccountPayoutEntryDraft: Hashable, Codable, Sendable {
    var amountDigits: String
    var payoutDate: Date
    var note: String
}

/// Whitelisted public profile account card (`rpc_v1_profile_account_insights`).
nonisolated struct ProfileAccountInsight: Hashable, Codable, Sendable, Identifiable {
    var id: TradingAccountID
    var name: String
    var category: TradingAccountCategory
    var mode: TradingAccountMode
    var customStatus: String?
    var payoutTotal: Money
    var payouts: [AccountPayoutEntry]
}

enum TradingAccountDropdownFilter {
    /// Accounts eligible for Add Trade / CSV import pickers.
    static func selectableForNewTrades(_ accounts: [TradingAccount]) -> [TradingAccount] {
        accounts.filter { $0.isActive && $0.canAddTrades && $0.showInAccountDropdowns }
    }

    /// Account filter menus — preserves a hidden-but-selected account in the menu.
    static func menuAccounts(
        from accounts: [TradingAccount],
        preservingSelection selectedID: TradingAccountID?
    ) -> [TradingAccount] {
        var visible = accounts.filter(\.showInAccountDropdowns)
        if let selectedID,
           !visible.contains(where: { $0.id == selectedID }),
           let selected = accounts.first(where: { $0.id == selectedID }) {
            visible.append(selected)
        }
        return visible.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Optional account selectors (achievements, etc.).
    static func selectableForLinking(_ accounts: [TradingAccount]) -> [TradingAccount] {
        accounts.filter { $0.isActive && $0.showInAccountDropdowns }
    }
}
