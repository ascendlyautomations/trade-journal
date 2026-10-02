import Foundation

/// Owner-managed manual payout row (`account_payout_entries`).
nonisolated struct AccountPayoutEntry: Hashable, Codable, Sendable, Identifiable {
    var id: AccountPayoutEntryID
    var accountID: TradingAccountID
    var amount: Money
    var payoutDate: Date
    var note: String?
    /// Owner screenshot on `account_payout_entries.image_url`. Omitted from public profile insights.
    var imageURL: String? = nil
}

/// How an edit writes `image_url`. `.unchanged` omits the column so a note-only save keeps the picture.
nonisolated enum PayoutEntryImageWrite: Hashable, Sendable {
    case unchanged
    case set(String)
    case clear
}

nonisolated struct AccountPayoutEntryDraft: Hashable, Codable, Sendable {
    var amountDigits: String
    var payoutDate: Date
    var note: String
    /// Saved picture URL when editing. Not written until ``PayoutEntryImageWrite`` says so.
    var imageURL: String? = nil
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
    /// Accounts offered in new-trade pickers: active and shown in dropdowns.
    static func selectableForNewTrades(_ accounts: [TradingAccount]) -> [TradingAccount] {
        accounts.filter { $0.isActive && $0.showInAccountDropdowns }
    }

    /// Add Trade account picker — visibility follows Settings “Display in account dropdowns”.
    static func visibleForManualTradePicker(
        from accounts: [TradingAccount],
        preservingSelection selectedID: TradingAccountID?
    ) -> [TradingAccount] {
        var visible = accounts.filter { $0.isActive && $0.showInAccountDropdowns }
        if let selectedID,
           !visible.contains(where: { $0.id == selectedID }),
           let selected = accounts.first(where: { $0.id == selectedID })
        {
            visible.append(selected)
        }
        return visible.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
