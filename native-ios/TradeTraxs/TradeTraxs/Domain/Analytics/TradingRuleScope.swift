import Foundation

/// Mirrors `lib/analytics/tradingRuleScope.ts`.
nonisolated enum TradingRuleScope: String, Codable, CaseIterable, Sendable {
    case combined
    case perAccount = "per_account"

    static let scopeOptions: [(id: TradingRuleScope, label: String)] = [
        (.combined, "All Accounts Combined"),
        (.perAccount, "Per Account"),
    ]
}

nonisolated enum TradingRuleWeekday: String, CaseIterable, Sendable, Codable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    static let displayOrder: [TradingRuleWeekday] = allCases

    var displayLabel: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

nonisolated enum TradingRuleScopeMath {
    private static let eastern = TimeZone(identifier: "America/New_York") ?? .gmt

    static func normalizeScope(_ value: String?) -> TradingRuleScope {
        guard let value else { return .combined }
        return TradingRuleScope(rawValue: value) ?? .combined
    }

    static func scopeBucketLabel(_ scope: TradingRuleScope) -> String {
        scope == .perAccount ? "per account" : "all accounts combined"
    }

    static func scopedDayBucket(dayKey: String, accountID: String?, scope: TradingRuleScope) -> String {
        if scope == .perAccount {
            return "\(dayKey)::\(accountID ?? "unassigned")"
        }
        return dayKey
    }

    static func scopedWeekBucket(weekKey: String, accountID: String?, scope: TradingRuleScope) -> String {
        if scope == .perAccount {
            return "\(weekKey)::\(accountID ?? "unassigned")"
        }
        return weekKey
    }

    static func easternWeekday(from date: Date) -> TradingRuleWeekday? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = eastern
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        let raw = formatter.string(from: date).lowercased()
        return TradingRuleWeekday(rawValue: raw)
    }

    static func easternWeekKey(from date: Date) -> String? {
        let dayKey = TradingSessionLabel.easternTradeDateString(from: date)
        guard !dayKey.isEmpty else { return nil }
        return easternWeekKey(dayKey: dayKey, from: date)
    }

    /// Monday-start Eastern week label `YYYY-MM-DD` for the week's Monday.
    /// Matches `easternWeekKeyFromDayKey` in web `tradingRuleScope.ts` (Eastern trade day key + instant weekday).
    static func easternWeekKey(dayKey: String, from date: Date) -> String? {
        guard let weekday = easternWeekday(from: date) else { return nil }
        let index = TradingRuleWeekday.displayOrder.firstIndex(of: weekday) ?? -1
        guard index >= 0 else { return nil }
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 > 0 }) else { return nil }
        let y = parts[0]
        let m = parts[1]
        let d = parts[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = y
        components.month = m
        components.day = d
        guard let tradeDateUTC = calendar.date(from: components),
              let monday = calendar.date(byAdding: .day, value: -index, to: tradeDateUTC)
        else { return nil }
        let mondayParts = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: monday)
        guard let mondayYear = mondayParts.year,
              let mondayMonth = mondayParts.month,
              let mondayDay = mondayParts.day
        else { return nil }
        return String(format: "%04d-%02d-%02d", mondayYear, mondayMonth, mondayDay)
    }

    static func normalizeAllowedTradingDays(_ values: [String]) -> [TradingRuleWeekday] {
        var seen = Set<String>()
        for value in values {
            let day = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard TradingRuleWeekday(rawValue: day) != nil, !seen.contains(day) else { continue }
            seen.insert(day)
        }
        return TradingRuleWeekday.displayOrder.filter { seen.contains($0.rawValue) }
    }
}
