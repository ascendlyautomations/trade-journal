import Foundation

/// Account-type gates for native payout flows (V1).
nonisolated enum PropFirmPayoutPolicy {
    /// Funded prop-firm accounts use `record_account_payout` + cycle history.
    static func supportsRecordPayout(for account: TradingAccount) -> Bool {
        account.isPropFirmAccount && account.mode == .funded
    }

    /// Legacy private ledger (`account_payout_entries`) — not for funded prop cycles.
    static func supportsManualPayoutLedger(for account: TradingAccount) -> Bool {
        guard !supportsRecordPayout(for: account) else { return false }
        switch account.mode {
        case .evaluation, .sim, .backtest:
            return false
        default:
            return true
        }
    }

    /// Create → Withdrawal — live accounts using the manual payout ledger.
    static func supportsLiveWithdrawal(for account: TradingAccount) -> Bool {
        account.mode == .live && supportsManualPayoutLedger(for: account)
    }

    /// Create → Withdrawal — Live (manual ledger) or Funded prop-firm (cycle record flow).
    static func supportsWithdrawal(for account: TradingAccount) -> Bool {
        supportsRecordPayout(for: account) || supportsManualPayoutLedger(for: account)
    }
}
