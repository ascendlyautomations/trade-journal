import Foundation

/// Mirrors web `PayoutDrawdownBehavior` (`lib/propfirmMetrics.ts`).
nonisolated enum PayoutDrawdownBehavior: String, Codable, Sendable, Hashable, CaseIterable {
    case resetToAccount = "reset_to_account"
    case keepTrailing = "keep_trailing"

    var title: String {
        switch self {
        case .resetToAccount: return "Reset drawdown to account value"
        case .keepTrailing: return "Keep trailing drawdown"
        }
    }

    var subtitle: String {
        switch self {
        case .resetToAccount:
            return "Drawdown floor returns to your starting account balance."
        case .keepTrailing:
            return "Trailing drawdown floor stays at the current level."
        }
    }
}

/// Closed or open payout cycle row — mirrors web `AccountPayoutCycle`.
nonisolated struct AccountPayoutCycle: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var accountID: TradingAccountID
    var startedAt: Date
    var endedAt: Date?
    var cycleStartBalance: Decimal
    var payoutAmount: Decimal?
    var note: String?
    var balanceBeforePayout: Decimal?
    var balanceAfterPayout: Decimal?
    var drawdownBehavior: PayoutDrawdownBehavior?
    var drawdownFloorAfterPayout: Decimal?
    var cycleNumber: Int?
}

/// Input for `record_account_payout` — mirrors web `RecordAccountPayoutInput`.
nonisolated struct RecordAccountPayoutInput: Hashable, Sendable {
    var balanceAfterPayout: Decimal
    var payoutAmount: Decimal
    var drawdownBehavior: PayoutDrawdownBehavior
    var drawdownFloorAfterPayout: Decimal
    var balanceBeforePayout: Decimal
    var rememberDrawdownBehavior: Bool
}

nonisolated struct RecordAccountPayoutResult: Sendable {
    var cycleID: String
    var accountPreferences: AccountPayoutPreferences?
}

nonisolated struct AccountPayoutPreferences: Hashable, Sendable {
    var payoutDrawdownBehavior: PayoutDrawdownBehavior?
    var rememberPayoutDrawdownBehavior: Bool
}

/// Setup context for Record Payout UI — mirrors web `fetchPropFirmPayoutSetupContext`.
nonisolated struct PropFirmPayoutSetupContext: Sendable {
    var account: TradingAccount
    var activeCycle: AccountPayoutCycle?
    var startingBalance: Decimal
    var balanceBeforePayout: Decimal
    var defaultDrawdownBehavior: PayoutDrawdownBehavior
    var defaultRememberDrawdownBehavior: Bool
    var cycleTrailingMetrics: PropFirmMetrics.TrailingDrawdownResult
}
