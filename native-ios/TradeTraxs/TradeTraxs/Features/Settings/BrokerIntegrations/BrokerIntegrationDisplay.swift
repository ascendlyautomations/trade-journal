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

    static func linkStatusLabel(for account: BrokerIntegrationAccount) -> String {
        if account.isLinked {
            if let name = account.tradetraxsAccountName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty
            {
                return "Linked to \(name)"
            }
            return "Linked"
        }
        switch account.status {
        case .discovered: return "Not linked"
        case .inactive: return "Inactive"
        case .linked: return "Linked"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
