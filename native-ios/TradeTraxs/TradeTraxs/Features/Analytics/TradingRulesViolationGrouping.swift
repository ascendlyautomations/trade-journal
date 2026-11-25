import Foundation

enum TradingRulesViolationGrouping {
    struct RuleGroup: Identifiable, Sendable {
        var id: String { ruleID.rawValue }
        var ruleID: TradingRulesComplianceAnalytics.RuleID
        var ruleLabel: String
        var violationCount: Int
        var violations: [TradingRulesComplianceAnalytics.ViolationEvent]
    }

    static func ruleGroups(
        from violations: [TradingRulesComplianceAnalytics.ViolationEvent]
    ) -> [RuleGroup] {
        let grouped = Dictionary(grouping: violations, by: \.ruleID)
        let groups = grouped.map { ruleID, events in
            let sorted = events.sorted { $0.at > $1.at }
            let label = sorted.first?.ruleLabel ?? ruleID.displayLabel
            return RuleGroup(
                ruleID: ruleID,
                ruleLabel: label,
                violationCount: events.count,
                violations: sorted
            )
        }
        return groups.sorted { lhs, rhs in
            if lhs.violationCount != rhs.violationCount {
                return lhs.violationCount > rhs.violationCount
            }
            return lhs.ruleLabel.localizedCaseInsensitiveCompare(rhs.ruleLabel) == .orderedAscending
        }
    }

    static func violationsByDayKey(
        _ violations: [TradingRulesComplianceAnalytics.ViolationEvent]
    ) -> [(dayKey: String, violations: [TradingRulesComplianceAnalytics.ViolationEvent])] {
        let grouped = Dictionary(grouping: violations, by: \.dayKey)
        let keys = grouped.keys.sorted(by: >)
        return keys.map { key in
            let events = grouped[key]?.sorted { $0.at > $1.at } ?? []
            return (dayKey: key, violations: events)
        }
    }
}

extension TradingRulesComplianceAnalytics.RuleID {
    fileprivate var displayLabel: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}