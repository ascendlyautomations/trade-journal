import Foundation

/// One `PreferenceComplianceEngine.rules` resolution per trade input for a single analytics pass.
nonisolated struct TradingRulesResolvedRulesCache: Sendable {
    private let rulesByKey: [UInt64: ResolvedTradingPreferences]
    private let ordered: [ResolvedTradingPreferences]

    init(context: PreferenceRuleContext?, inputs: [PreferenceComplianceEngine.Input]) {
        ordered = inputs.map {
            PreferenceComplianceEngine.rules(in: context, at: $0.at, accountID: $0.accountID)
        }
        var map: [UInt64: ResolvedTradingPreferences] = [:]
        map.reserveCapacity(inputs.count)
        for (index, input) in inputs.enumerated() {
            map[Self.key(for: input)] = ordered[index]
        }
        rulesByKey = map
    }

    func rules(at index: Int) -> ResolvedTradingPreferences {
        guard ordered.indices.contains(index) else { return .empty }
        return ordered[index]
    }

    func rules(for input: PreferenceComplianceEngine.Input) -> ResolvedTradingPreferences {
        rulesByKey[Self.key(for: input)] ?? .empty
    }

    static func key(for input: PreferenceComplianceEngine.Input) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(input.at.timeIntervalSince1970)
        hasher.combine(input.accountID)
        hasher.combine(input.tradeID)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}
