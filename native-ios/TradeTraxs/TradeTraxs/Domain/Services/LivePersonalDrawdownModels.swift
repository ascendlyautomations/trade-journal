import Foundation

/// Web `LivePersonalDrawdownType` — fixed vs trailing personal floor on live accounts.
nonisolated enum LivePersonalDrawdownType: String, Sendable, Hashable, CaseIterable, Codable {
    case fixed
    case trailing

    var displayTitle: String {
        switch self {
        case .fixed: return "Fixed"
        case .trailing: return "Trailing"
        }
    }
}

nonisolated struct LivePersonalDrawdownConfig: Sendable, Hashable {
    var limitAmount: Decimal
    var limitType: LivePersonalDrawdownType
}

/// Persisted gear state for one live account (`accounts.max_drawdown` / `drawdown_type`).
nonisolated struct LivePersonalDrawdownStored: Sendable, Hashable, Codable {
    var limitAmount: Decimal?
    var limitType: LivePersonalDrawdownType
}

nonisolated struct LivePersonalDrawdownEquitySample: Sendable, Hashable {
    var date: Date
    var equity: Decimal
    var drawdownFloor: Decimal?
}

nonisolated enum LiveWithdrawalDrawdownBehavior: String, Sendable {
    case resetToAccount = "reset_to_account"
    case keepTrailing = "keep_trailing"
}
