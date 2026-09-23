import Foundation

/// Pure calendar daily-range intent merge (ET civil `YYYY-MM-DD` bounds).
nonisolated enum AnalyticsCalendarRangeCoalescing {
    static func merge(_ intents: [AnalyticsCalendarRangeIntent]) -> [AnalyticsCalendarRangeIntent] {
        guard !intents.isEmpty else { return [] }

        var grouped: [AnalyticsCalendarRangeCoalescingKey: [AnalyticsCalendarRangeIntent]] = [:]
        for intent in intents {
            grouped[intent.coalescingKey, default: []].append(intent)
        }

        var merged: [AnalyticsCalendarRangeIntent] = []
        for (_, bucket) in grouped {
            merged.append(contentsOf: mergeSameScope(bucket))
        }
        return merged.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.endDate < rhs.endDate
        }
    }

    private static func mergeSameScope(_ intents: [AnalyticsCalendarRangeIntent]) -> [AnalyticsCalendarRangeIntent] {
        guard !intents.isEmpty else { return [] }
        let sorted = intents.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.endDate < $1.endDate
        }

        var output: [AnalyticsCalendarRangeIntent] = []
        var current = sorted[0]

        for next in sorted.dropFirst() {
            if canMerge(current, next) {
                current = AnalyticsCalendarRangeIntent(
                    viewerID: current.viewerID,
                    startDate: min(current.startDate, next.startDate),
                    endDate: max(current.endDate, next.endDate),
                    accountScope: current.accountScope,
                    modeScope: current.modeScope,
                    targetRevision: maxOptionalRevision(current.targetRevision, next.targetRevision)
                )
            } else {
                output.append(current)
                current = next
            }
        }
        output.append(current)
        return output
    }

    private static func canMerge(_ lhs: AnalyticsCalendarRangeIntent, _ rhs: AnalyticsCalendarRangeIntent) -> Bool {
        guard lhs.viewerID == rhs.viewerID,
              lhs.accountScope == rhs.accountScope,
              lhs.modeScope == rhs.modeScope
        else { return false }
        return rangesOverlapOrAdjacent(
            startA: lhs.startDate,
            endA: lhs.endDate,
            startB: rhs.startDate,
            endB: rhs.endDate
        )
    }

    static func rangesOverlapOrAdjacent(
        startA: String,
        endA: String,
        startB: String,
        endB: String
    ) -> Bool {
        guard civilDateOrder(startA) <= civilDateOrder(endA),
              civilDateOrder(startB) <= civilDateOrder(endB)
        else { return false }

        if civilDateOrder(startA) <= civilDateOrder(endB),
           civilDateOrder(startB) <= civilDateOrder(endA) {
            return true
        }

        if civilDateOrder(addCivilDays(to: endA, days: 1)) == civilDateOrder(startB) {
            return true
        }
        if civilDateOrder(addCivilDays(to: endB, days: 1)) == civilDateOrder(startA) {
            return true
        }
        return false
    }

    private static func civilDateOrder(_ key: String) -> Int {
        guard let parts = AnalyticsCalendarDay.components(from: key) else { return Int.max }
        return parts.year * 10_000 + parts.month * 100 + parts.day
    }

    private static func maxOptionalRevision(_ lhs: Int64?, _ rhs: Int64?) -> Int64? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, let r?):
            return r
        case (let l?, nil):
            return l
        case (let l?, let r?):
            return max(l, r)
        }
    }

    private static func addCivilDays(to key: String, days: Int) -> String {
        guard let parts = AnalyticsCalendarDay.components(from: key) else { return key }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsCalendarDay.timeZone
        guard
            let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: AnalyticsCalendarDay.timeZone,
                year: parts.year,
                month: parts.month,
                day: parts.day
            )),
            let shifted = calendar.date(byAdding: .day, value: days, to: date),
            let next = AnalyticsCalendarDay.key(for: shifted)
        else { return key }
        return next
    }
}
