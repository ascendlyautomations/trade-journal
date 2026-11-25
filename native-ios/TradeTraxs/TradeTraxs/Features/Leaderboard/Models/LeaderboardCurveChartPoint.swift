import Foundation

enum LeaderboardDisplayMode: String, Equatable, Sendable {
    case rankings
    case curve
}

enum LeaderboardCurveSeries: String, CaseIterable, Hashable, Sendable {
    case highest
    case you
    case average
    case lowest

    /// Stable Swift Charts series identifier (explicit coloring + grouping).
    var chartKey: String { rawValue }
}

nonisolated struct LeaderboardCurveChartPoint: Hashable, Identifiable, Sendable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let highest: Double?
    let lowest: Double?
    let you: Double?
    let average: Double?

    init(
        dayKey: String,
        date: Date,
        highest: Double?,
        lowest: Double?,
        you: Double?,
        average: Double?
    ) {
        self.dayKey = String(dayKey.prefix(10))
        self.date = date
        self.highest = highest
        self.lowest = lowest
        self.you = you
        self.average = average
    }

    init?(wire: LeaderboardCurveV1.CurvePoint) {
        let normalizedDay = String(wire.day.prefix(10))
        guard let parsed = Self.parseDay(normalizedDay) else { return nil }
        dayKey = normalizedDay
        date = parsed
        highest = LeaderboardCurveChartData.sanitizedMetric(wire.highest?.value)
        lowest = LeaderboardCurveChartData.sanitizedMetric(wire.lowest?.value)
        you = LeaderboardCurveChartData.sanitizedMetric(wire.you?.value)
        average = LeaderboardCurveChartData.sanitizedMetric(wire.average?.value)
    }

    func value(for series: LeaderboardCurveSeries) -> Double? {
        switch series {
        case .highest: return highest
        case .you: return you
        case .average: return average
        case .lowest: return lowest
        }
    }

    static func parseDay(_ raw: String) -> Date? {
        let key = String(raw.prefix(10))
        guard key.count == 10 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }
}

nonisolated struct LeaderboardCurvePlotMark: Identifiable, Hashable, Sendable {
    var id: String { "\(series.chartKey)|\(dayKey)" }
    let series: LeaderboardCurveSeries
    let dayKey: String
    let date: Date
    let value: Double
}

/// Normalizes RPC curve days into chronologically ordered, de-duplicated chart input.
nonisolated enum LeaderboardCurveChartData {
    struct Prepared: Equatable, Sendable {
        var days: [LeaderboardCurveChartPoint]
        var marks: [LeaderboardCurvePlotMark]

        func marks(for series: LeaderboardCurveSeries) -> [LeaderboardCurvePlotMark] {
            marks.filter { $0.series == series }
        }

        func plotValue(for series: LeaderboardCurveSeries, dayKey: String) -> Double? {
            marks.first { $0.series == series && $0.dayKey == dayKey }?.value
        }
    }

    static func sanitizedMetric(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        return raw
    }

    static func preparePoints(from wire: [LeaderboardCurveV1.CurvePoint]) -> [LeaderboardCurveChartPoint] {
        prepare(points: wire.compactMap(LeaderboardCurveChartPoint.init(wire:))).days
    }

    static func prepare(points: [LeaderboardCurveChartPoint]) -> Prepared {
        let days = dedupeAndSort(points)
        var marks: [LeaderboardCurvePlotMark] = []
        marks.reserveCapacity(days.count * LeaderboardCurveSeries.allCases.count)

        for series in LeaderboardCurveSeries.allCases {
            marks.append(contentsOf: carryForwardMarks(for: series, days: days))
        }

        return Prepared(days: days, marks: marks)
    }

    /// Step-holds the last known value across chart days (no interpolation between undefined stretches).
    private static func carryForwardMarks(
        for series: LeaderboardCurveSeries,
        days: [LeaderboardCurveChartPoint]
    ) -> [LeaderboardCurvePlotMark] {
        var lastKnown: Double?
        var out: [LeaderboardCurvePlotMark] = []
        out.reserveCapacity(days.count)
        for day in days {
            if let value = day.value(for: series) {
                lastKnown = value
            }
            guard let plotValue = lastKnown else { continue }
            out.append(
                LeaderboardCurvePlotMark(
                    series: series,
                    dayKey: day.dayKey,
                    date: day.date,
                    value: plotValue
                )
            )
        }
        return out
    }

    private static func dedupeAndSort(_ points: [LeaderboardCurveChartPoint]) -> [LeaderboardCurveChartPoint] {
        var byDay: [String: LeaderboardCurveChartPoint] = [:]
        for point in points {
            let key = String(point.dayKey.prefix(10))
            if byDay[key] == nil {
                byDay[key] = point
            }
        }
        return byDay.values.sorted { lhs, rhs in
            if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
            return lhs.date < rhs.date
        }
    }
}

extension LeaderboardCategory {
    nonisolated var supportsCurveChart: Bool { true }

    /// When true, tooltip/chart Y-axis use integer-style counts (streak, followers).
    nonisolated var curveUsesIntegerAxis: Bool {
        switch self {
        case .winStreak, .followers:
            return true
        default:
            return false
        }
    }
}