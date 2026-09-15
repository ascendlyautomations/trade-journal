import Foundation

enum BrokerIntegrationDisplay {
    static func maskedAccountNumber(_ externalAccountId: String, name: String?) -> String {
        let source = name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? externalAccountId
        if let suffix = TradingAccountDisplay.maskedAccountNumberSuffix(source) {
            return suffix
        }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return "••••" }
        return "•••• \(trimmed.suffix(4))"
    }

    static func providerLabel(_ provider: BrokerIntegrationProvider) -> String {
        switch provider {
        case .tradovate: return "Tradovate"
        case .rithmic: return "Rithmic"
        }
    }

    /// Broker import sheet secondary line: `Tradovate · Alpha Futures · Eval · 0003`.
    static func brokerImportMetadataLine(
        provider: BrokerIntegrationProvider,
        tradetraxsAccountName: String?,
        tradingAccounts: [TradingAccount]
    ) -> String {
        let providerPart = providerLabel(provider)
        if let linked = resolveLinkedTradingAccount(named: tradetraxsAccountName, in: tradingAccounts) {
            return "\(providerPart) · \(TradingAccountDisplay.ownerDropdownLine(for: linked))"
        }
        if let name = tradetraxsAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return "\(providerPart) · \(name)"
        }
        return providerPart
    }

    private static func resolveLinkedTradingAccount(
        named tradetraxsAccountName: String?,
        in accounts: [TradingAccount]
    ) -> TradingAccount? {
        guard let raw = tradetraxsAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        if let match = accounts.first(where: { $0.name == raw }) {
            return match
        }
        return accounts.first(where: { TradingAccountDisplay.ownerDropdownLine(for: $0) == raw })
    }

    static func linkStatusLabel(for account: BrokerIntegrationAccount) -> String {
        if account.hasTradetraxsMapping {
            return linkedTradeTraxsLine(for: account, tradingAccounts: []) ?? "Linked"
        }
        switch account.status {
        case .discovered: return "Not linked"
        case .inactive: return "Inactive"
        case .linked: return "Linked"
        }
    }

    /// Owner-facing link line, e.g. `Linked to: Alpha Futures · Eval · 0003`.
    static func linkedTradeTraxsLine(
        for account: BrokerIntegrationAccount,
        tradingAccounts: [TradingAccount]
    ) -> String? {
        guard account.hasTradetraxsMapping else { return nil }
        if let rawID = account.tradetraxsAccountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawID.isEmpty,
           let match = tradingAccounts.first(where: { $0.id.rawValue == rawID })
        {
            return "Linked to: \(TradingAccountDisplay.ownerDropdownLine(for: match))"
        }
        if let name = account.tradetraxsAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return "Linked to: \(name)"
        }
        return "Linked"
    }

    static func importResultMessage(newTradeCount: Int) -> String {
        switch newTradeCount {
        case 0: return "No new trades found"
        case 1: return "1 new trade imported"
        default: return "\(newTradeCount) new trades imported"
        }
    }

    static func importFailureMessage(for error: Error) -> String {
        let detail = UserFacingError.message(for: error)
        let lowered = detail.lowercased()
        if lowered.contains("reconnect")
            || lowered.contains("authorize")
            || lowered.contains("sign in")
            || lowered.contains("session")
            || lowered.contains("authentication")
        {
            return detail
        }
        return "Unable to import trades. Please try again."
    }

    static func importFailureMessage(serverSummary: String?) -> String {
        guard let summary = serverSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty
        else {
            return "Unable to import trades. Please try again."
        }
        let lowered = summary.lowercased()
        if lowered.contains("reconnect")
            || lowered.contains("authorize")
            || lowered.contains("sign in")
        {
            return summary
        }
        return "Unable to import trades. Please try again."
    }
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
