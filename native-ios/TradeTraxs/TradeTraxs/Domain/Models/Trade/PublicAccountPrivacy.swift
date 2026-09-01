import Foundation

/// Public/shared account privacy — mirrors web `lib/publicAccountPrivacy.ts`.
///
/// Account numbers and owner-only identifiers must never appear on profile, feed,
/// messages, or other shared surfaces. Names that embed account numbers are replaced
/// with generic mode/category labels.
nonisolated enum PublicAccountPrivacy {
    static let forbiddenPublicAccountKeys: Set<String> = [
        "account_number",
        "locked_account_number",
        "locked_account_name",
        "locked_account_id",
        "source_account_id",
    ]

    static let forbiddenPublicTradeAccountKeys: Set<String> = [
        "account_name",
        "account_id",
        "account_size",
    ]

    /// True when `name` equals or contains the normalized account number.
    static func nameEmbedsAccountNumber(name: String, accountNumber: String?) -> Bool {
        guard let number = TradingAccountDisplay.normalizedAccountNumber(accountNumber) else {
            return false
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if trimmedName.compare(number, options: .caseInsensitive) == .orderedSame {
            return true
        }
        return trimmedName.range(of: number, options: .caseInsensitive) != nil
    }

    /// Generic public label from account category/mode (never includes account number).
    static func defaultPublicAccountLabel(
        category: TradingAccountCategory?,
        mode: TradingAccountMode?
    ) -> String {
        let category = category ?? .personal
        switch category {
        case .propFirm:
            return mode == .funded ? "Funded Account" : "Evaluation Account"
        case .backtest:
            return "Backtest Account"
        case .personal, .broker:
            switch mode {
            case .sim: return "Sim Account"
            case .backtest: return "Backtest Account"
            default: return "Live Account"
            }
        }
    }

    /// Safe public account title — strips embedded numbers; never appends `#account_number`.
    static func publicSafeAccountName(
        rawName: String?,
        accountNumber: String?,
        category: TradingAccountCategory?,
        mode: TradingAccountMode?
    ) -> String {
        let trimmed = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || nameEmbedsAccountNumber(name: trimmed, accountNumber: accountNumber) {
            return defaultPublicAccountLabel(category: category, mode: mode)
        }
        return trimmed
    }

    static func publicSafeAccountName(for account: TradingAccount) -> String {
        publicSafeAccountName(
            rawName: account.name,
            accountNumber: account.accountNumber,
            category: account.category,
            mode: account.mode
        )
    }

    /// Profile/public trade card label from trade mode only (no account table fetch).
    static func publicTradeAccountLabel(mode: TradeMode) -> String? {
        switch mode {
        case .live: return "Live Account"
        case .sim: return "Sim Account"
        case .backtest: return "Backtest Account"
        case .replay: return "Trading Account"
        case .copyTraded: return "Trading Account"
        }
    }

    /// Owner trade write — public trades store sanitized denormalized account fields only.
    static func sanitizedTradeAccountFieldsForSave(
        accountName: String?,
        accountSize: String?,
        accountNumber: String?,
        category: TradingAccountCategory?,
        mode: TradingAccountMode?,
        isPublic: Bool
    ) -> (accountName: String?, accountSize: String?) {
        guard isPublic else {
            return (accountName, accountSize)
        }
        let safeName = publicSafeAccountName(
            rawName: accountName,
            accountNumber: accountNumber,
            category: category,
            mode: mode
        )
        return (safeName, nil)
    }

    /// Returns true when encoded JSON contains forbidden account-identifier keys or values.
    static func jsonContainsForbiddenAccountIdentifier(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return false }
        return containsForbiddenAccountIdentifier(object)
    }

    private static func containsForbiddenAccountIdentifier(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            for (key, nested) in dict {
                if forbiddenPublicAccountKeys.contains(key)
                    || forbiddenPublicTradeAccountKeys.contains(key) {
                    return true
                }
                if containsForbiddenAccountIdentifier(nested) { return true }
            }
            return false
        }
        if let array = value as? [Any] {
            return array.contains { containsForbiddenAccountIdentifier($0) }
        }
        return false
    }
}
