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

    /// Middle-dot separator for owner dropdown lines — distinct from masking bullets (`••••`).
    static let ownerDropdownSeparator = " · "

    /// Normalized account number for display (trimmed; empty → nil).
    static func normalizedAccountNumber(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func title(
        name: String?,
        accountNumber: String? = nil,
        audience: Audience,
        category: TradingAccountCategory? = nil,
        mode: TradingAccountMode? = nil
    ) -> String {
        switch audience {
        case .public:
            return PublicAccountPrivacy.publicSafeAccountName(
                rawName: name,
                accountNumber: accountNumber,
                category: category,
                mode: mode
            )
        case .owner:
            let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = normalizedAccountNumber(accountNumber) else {
                return trimmedName
            }
            if trimmedName.isEmpty { return number }
            return "\(trimmedName)\(separator)\(number)"
        }
    }

    static func title(for account: TradingAccount, audience: Audience) -> String {
        title(
            name: account.name,
            accountNumber: account.accountNumber,
            audience: audience,
            category: account.category,
            mode: account.mode
        )
    }

    /// Optional wrapper — nil when the resulting title is empty.
    static func optionalTitle(
        name: String?,
        accountNumber: String? = nil,
        audience: Audience,
        category: TradingAccountCategory? = nil,
        mode: TradingAccountMode? = nil
    ) -> String? {
        let value = title(
            name: name,
            accountNumber: accountNumber,
            audience: audience,
            category: category,
            mode: mode
        )
        return value.isEmpty ? nil : value
    }

    // MARK: - Owner account dropdown (private selectors)

    /// Compact mode label from authoritative `TradingAccountMode` — never inferred from name.
    static func ownerDropdownModeLabel(_ mode: TradingAccountMode) -> String {
        switch mode {
        case .evaluation: return "Eval"
        case .funded: return "Funded"
        case .live: return "Live"
        case .backtest: return "Backtest"
        case .sim: return "Sim"
        }
    }

    /// Owner-only suffix: `••••1234` for longer values; short values (≤4) shown in full.
    /// Already-masked values (`••••1234`, `****1234`, etc.) are normalized — never masked twice.
    static func maskedAccountNumberSuffix(_ raw: String?) -> String? {
        guard let normalized = normalizedAccountNumber(raw) else { return nil }

        if let canonical = canonicalMaskedAccountNumberSuffix(normalized) {
            return canonical
        }

        if normalized.count <= 4 {
            return normalized
        }

        let trailingDigits = trailingAccountDigits(from: normalized)
        guard trailingDigits.count == 4 else {
            return "••••" + String(normalized.suffix(4))
        }
        return "••••" + trailingDigits
    }

    /// Returns canonical `••••` + up to four trailing digits when `raw` is already masked.
    private static func canonicalMaskedAccountNumberSuffix(_ normalized: String) -> String? {
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 5 else { return nil }

        let maskPrefix = compact.prefix(4)
        guard maskPrefix.allSatisfy({ $0 == "•" || $0 == "*" }) else { return nil }

        let digits = compact.dropFirst(4).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        return "••••" + String(digits.suffix(4))
    }

    private static func trailingAccountDigits(from normalized: String) -> String {
        String(normalized.filter(\.isNumber).suffix(4))
    }

    /// Single-line owner dropdown label: `Name · Mode · ••••4821`.
    static func ownerDropdownLine(for account: TradingAccount) -> String {
        ownerDropdownLine(
            name: account.name,
            mode: account.mode,
            accountNumber: account.accountNumber
        )
    }

    static func ownerDropdownLine(
        name: String?,
        mode: TradingAccountMode,
        accountNumber: String?
    ) -> String {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !trimmedName.isEmpty {
            parts.append(trimmedName)
        }
        parts.append(ownerDropdownModeLabel(mode))
        if let suffix = maskedAccountNumberSuffix(accountNumber) {
            parts.append(suffix)
        }
        return parts.joined(separator: ownerDropdownSeparator)
    }

    /// Prop-firm grouping label from account name — mirrors web `inferPropFirmName`.
    static func inferPropFirmName(_ accountName: String?) -> String {
        let name = (accountName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        let pattern = #"\s+\$?[\d,]+(?:\.\d+)?\s*[kK]?$"#
        if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let trimmed = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? name : trimmed
        }
        return name
    }

    static func propFirmName(for account: TradingAccount) -> String? {
        guard account.isPropFirmAccount else { return nil }
        let firm = inferPropFirmName(account.name)
        return firm.isEmpty ? nil : firm
    }
}
