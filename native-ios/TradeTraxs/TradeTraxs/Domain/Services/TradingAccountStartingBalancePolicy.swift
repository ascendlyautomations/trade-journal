import Foundation

/// Persisted `accounts.account_size` as opening equity, never inferred from trade history.
nonisolated enum TradingAccountStartingBalancePolicy {
    static let requiredMessage = "Account Value is required."

    static let liveLedgerMessage =
        "Account Value is required for equity and drawdown tracking. Enter the balance you started with."

    /// Create gate for Personal / Broker / Prop Firm (Backtest may omit size unless drawdown is enabled).
    static func requiresStartingBalanceOnCreate(
        _ draft: TradingAccountDraft,
        livePersonalDrawdown: LivePersonalDrawdownConfig? = nil
    ) -> Bool {
        switch draft.category {
        case .personal, .broker, .propFirm:
            return true
        case .backtest:
            guard let config = livePersonalDrawdown, config.limitAmount > 0 else { return false }
            return true
        }
    }

    /// Save gate when the account uses manual-ledger live equity (`account_size` is the baseline).
    static func requiresStartingBalanceOnSave(
        _ draft: TradingAccountDraft,
        drawdownConfiguredOnAccount account: TradingAccount? = nil
    ) -> Bool {
        switch draft.category {
        case .personal, .broker:
            return true
        case .propFirm:
            return true
        case .backtest:
            if let account,
               let limit = account.livePersonalDrawdown?.limitAmount,
               limit > 0
            {
                return true
            }
            return false
        }
    }

    static func requiresStartingBalanceForBacktestDrawdown(
        draft: TradingAccountDraft,
        enableDrawdown: Bool
    ) -> Bool {
        draft.category == .backtest && enableDrawdown
    }

    static func parsedPositiveAmount(from sizeDigits: String) -> Decimal? {
        let plain = NumericInputFieldSupport.plainNumericString(from: sizeDigits)
        guard !plain.isEmpty, let amount = Decimal(string: plain), amount > 0 else { return nil }
        return amount
    }

    static func resolvedStartingBalance(for account: TradingAccount) -> Decimal? {
        let amount = PropFirmMetrics.parseAccountSize(account.size)
        return amount > 0 ? amount : nil
    }

    static func validationMessage(for sizeDigits: String, context: ValidationContext) -> String? {
        guard parsedPositiveAmount(from: sizeDigits) != nil else {
            return context == .liveLedger ? liveLedgerMessage : requiredMessage
        }
        return nil
    }

    enum ValidationContext: Sendable {
        case standard
        case liveLedger
    }
}