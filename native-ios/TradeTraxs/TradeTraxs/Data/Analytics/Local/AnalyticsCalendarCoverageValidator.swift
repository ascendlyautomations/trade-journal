import Foundation

/// Deterministic civil-date interval coverage for `analytics_range_coverage`.
nonisolated enum AnalyticsCalendarCoverageValidator {
    struct Segment: Equatable, Sendable {
        var start: String
        var end: String
        var serverRevision: Int64
    }

    static func evaluate(
        requestStart: String,
        requestEnd: String,
        requiredRevision: Int64,
        segments: [Segment]
    ) -> AnalyticsLocalReadState {
        let overlapping = segments.filter { overlaps($0.start, $0.end, requestStart, requestEnd) }
        if overlapping.isEmpty {
            return .missing
        }

        let atRequired = overlapping.filter { $0.serverRevision == requiredRevision }
        if fullyCovers(requestStart: requestStart, requestEnd: requestEnd, segments: atRequired) {
            return .available
        }

        if !atRequired.isEmpty {
            return .partial
        }

        let staleCandidates = overlapping.filter { $0.serverRevision != requiredRevision }
        if !staleCandidates.isEmpty {
            let found = staleCandidates.map(\.serverRevision).max()
            return .stale(foundRevision: found)
        }

        return .missing
    }

    static func segments(from records: [AnalyticsRangeCoverageRecord]) -> [Segment] {
        records.map {
            Segment(
                start: $0.start_date,
                end: $0.end_date,
                serverRevision: $0.server_revision
            )
        }
    }

    static func fullyCovers(
        requestStart: String,
        requestEnd: String,
        segments: [Segment]
    ) -> Bool {
        guard requestStart <= requestEnd else { return false }
        let clipped: [(String, String)] = segments.compactMap { seg in
            let start = maxDay(seg.start, requestStart)
            let end = minDay(seg.end, requestEnd)
            guard start <= end else { return nil }
            return (start, end)
        }
        if clipped.isEmpty { return false }

        let merged = mergeAdjacent(clipped.sorted { $0.0 < $1.0 })
        guard let first = merged.first, first.0 <= requestStart else { return false }
        var cursor = first.1
        if cursor >= requestEnd { return true }

        for interval in merged.dropFirst() {
            guard let dayAfterCursor = addDays(to: cursor, delta: 1) else { return false }
            if interval.0 > dayAfterCursor {
                return false
            }
            if interval.1 > cursor {
                cursor = interval.1
            }
            if cursor >= requestEnd { return true }
        }
        return cursor >= requestEnd
    }

    // MARK: - Civil date helpers (YYYY-MM-DD lex order)

    static func overlaps(_ aStart: String, _ aEnd: String, _ bStart: String, _ bEnd: String) -> Bool {
        aStart <= bEnd && bStart <= aEnd
    }

    private static func maxDay(_ a: String, _ b: String) -> String { a >= b ? a : b }
    private static func minDay(_ a: String, _ b: String) -> String { a <= b ? a : b }

    private static func mergeAdjacent(_ sorted: [(String, String)]) -> [(String, String)] {
        guard var current = sorted.first else { return [] }
        var merged: [(String, String)] = []
        for next in sorted.dropFirst() {
            guard let dayAfter = addDays(to: current.1, delta: 1) else {
                merged.append(current)
                current = next
                continue
            }
            if next.0 <= dayAfter {
                current.1 = maxDay(current.1, next.1)
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    static func addDays(to key: String, delta: Int) -> String? {
        guard let comps = AnalyticsCalendarDay.components(from: key) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsCalendarDay.timeZone
        guard
            let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: AnalyticsCalendarDay.timeZone,
                year: comps.year,
                month: comps.month,
                day: comps.day
            )),
            let shifted = calendar.date(byAdding: .day, value: delta, to: date)
        else { return nil }
        return AnalyticsCalendarDay.key(for: shifted)
    }
}
