import Foundation

/// Web `LivePersonalDrawdownType`, fixed vs trailing personal floor on live accounts.
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
    /// Max drawdown floor balance (`accounts.drawdown_floor_cap`). Nil = uncapped.
    var floorCap: Decimal? = nil
}

/// Persisted gear state for one live account (`accounts.max_drawdown` / `drawdown_type`).
nonisolated struct LivePersonalDrawdownStored: Sendable, Hashable, Codable {
    var limitAmount: Decimal?
    var limitType: LivePersonalDrawdownType
    var floorCap: Decimal? = nil
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

/// Supabase `accounts` drawdown columns, encodes explicit JSON nulls when clearing.
nonisolated struct LivePersonalDrawdownAccountPatchBody: Encodable, Sendable {
    var max_drawdown: Double?
    var drawdown_type: String?
    var drawdown_floor_cap: Double?

    enum CodingKeys: String, CodingKey {
        case max_drawdown
        case drawdown_type
        case drawdown_floor_cap
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let max_drawdown {
            try container.encode(max_drawdown, forKey: .max_drawdown)
        } else {
            try container.encodeNil(forKey: .max_drawdown)
        }
        if let drawdown_type {
            try container.encode(drawdown_type, forKey: .drawdown_type)
        } else {
            try container.encodeNil(forKey: .drawdown_type)
        }
        if let drawdown_floor_cap {
            try container.encode(drawdown_floor_cap, forKey: .drawdown_floor_cap)
        } else {
            try container.encodeNil(forKey: .drawdown_floor_cap)
        }
    }
}

extension TradingAccount {
    /// Keeps configured live drawdown when a stale bootstrap snapshot omits the columns.
    mutating func mergeLivePersonalDrawdownPreservingNewer(from prior: TradingAccount) {
        guard PropFirmPayoutPolicy.supportsLiveWithdrawal(for: self) else { return }
        let incomingConfigured = livePersonalDrawdown?.limitAmount.map { $0 > 0 } ?? false
        let priorConfigured = prior.livePersonalDrawdown?.limitAmount.map { $0 > 0 } ?? false
        if !incomingConfigured, priorConfigured {
            livePersonalDrawdown = prior.livePersonalDrawdown
            return
        }
        if incomingConfigured, priorConfigured,
           let priorStored = prior.livePersonalDrawdown,
           let incomingStored = livePersonalDrawdown
        {
            if priorStored.floorCap != nil, incomingStored.floorCap == nil {
                livePersonalDrawdown = LivePersonalDrawdownStored(
                    limitAmount: incomingStored.limitAmount ?? priorStored.limitAmount,
                    limitType: incomingStored.limitType,
                    floorCap: priorStored.floorCap
                )
            }
        }
    }
}
