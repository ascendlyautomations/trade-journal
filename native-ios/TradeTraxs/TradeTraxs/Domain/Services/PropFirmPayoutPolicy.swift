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
}
