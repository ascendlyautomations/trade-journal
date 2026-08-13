import Foundation

/// Single formatter for trading-account titles across native UI.
///
/// - Owner / private surfaces: `Account Name • Account Number` (number omitted when absent)
/// - Public surfaces: `Account Name` only — never expose account numbers
nonisolated enum TradingAccountDisplay {
    enum Audience: Sendable, Equatable {
        /// Dashboard, Add/Edit Trade, Calendar, Trades filters, Settings, own journal.
        case owner
        /// Profiles (visitor), Feed, Explore, Leaderboard, others' Trade Detail, shared content.
        case `public`
    }

    static let separator = " • "

    /// Normalized account number for display (trimmed; empty → nil).
    static func normalizedAccountNumber(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func title(
        name: String?,
        accountNumber: String? = nil,
        audience: Audience
    ) -> String {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch audience {
        case .public:
            return trimmedName
        case .owner:
            guard let number = normalizedAccountNumber(accountNumber) else {
                return trimmedName
            }
            if trimmedName.isEmpty { return number }
            return "\(trimmedName)\(separator)\(number)"
        }
    }

    static func title(for account: TradingAccount, audience: Audience) -> String {
        title(name: account.name, accountNumber: account.accountNumber, audience: audience)
    }

    /// Optional wrapper — nil when the resulting title is empty.
    static func optionalTitle(
        name: String?,
        accountNumber: String? = nil,
        audience: Audience
    ) -> String? {
        let value = title(name: name, accountNumber: accountNumber, audience: audience)
        return value.isEmpty ? nil : value
    }
}
