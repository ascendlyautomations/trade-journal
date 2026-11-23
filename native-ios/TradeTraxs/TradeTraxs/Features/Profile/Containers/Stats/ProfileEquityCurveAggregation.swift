import Foundation

/// Adaptive downsampling for equity curve rendering + scrubbing (full series stays in analytics).
nonisolated enum ProfileEquityCurveAggregation {
    enum DetailLevel: String, Sendable, Equatable {
        case trade
        case day
        case week
        case month

        var scrubKindLabel: String {
            switch self {
            case .trade: return "Trade"
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            }
        }
    }

    struct ScrubPoint: Sendable, Equatable {
        var equity: Decimal
        var drawdownFloor: Decimal?
        var anchorDate: Date?
        var periodStart: Date?
        var periodEnd: Date?
        var periodNetPnL: Decimal
        var detailLevel: DetailLevel
        var tradesInBucket: Int
    }

    static func targetDetailLevel(pointCount: Int) -> DetailLevel {
        switch pointCount {
        case ...30:
            return .trade
        case ...100:
            return .day
        case ...300:
            return .week
        default:
            return .month
        }
    }

    /// Chronological aggregation; keeps index-0 opening anchor when present.
    static func aggregateForDisplay(
        _ ordered: [ProfileStatisticsMetrics.EquityPoint]
    ) -> [ScrubPoint] {
        guard ordered.count >= 2 else {
            return ordered.map { singlePoint($0, level: .trade, tradesInBucket: 1) }
        }

        let level = resolvedDetailLevel(ordered)
        if level == .trade {
            return tradeLevelPoints(ordered)
        }

        var output: [ScrubPoint] = []
        let opening = ordered[0]
        output.append(singlePoint(opening, level: level, tradesInBucket: 1, periodNetPnL: 0))

        let rest = Array(ordered.dropFirst())
        let buckets = bucket(rest, level: level)
        var priorEquity = opening.equity

        for bucket in buckets {
            guard let last = bucket.points.last else { continue }
            let firstInBucket = bucket.points.first!
            let net = last.equity - firstInBucket.equity
            output.append(
                ScrubPoint(
                    equity: last.equity,
                    drawdownFloor: last.drawdownFloor,
                    anchorDate: last.date ?? bucket.periodEnd,
                    periodStart: bucket.periodStart,
                    periodEnd: bucket.periodEnd,
                    periodNetPnL: net,
                    detailLevel: level,
                    tradesInBucket: bucket.points.count
                )
            )
            priorEquity = last.equity
            _ = priorEquity
        }

        return output
    }

  private static func resolvedDetailLevel(
        _ ordered: [ProfileStatisticsMetrics.EquityPoint]
    ) -> DetailLevel {
        let target = targetDetailLevel(pointCount: ordered.count)
        guard target != .trade else { return .trade }
        let rest = Array(ordered.dropFirst())
        let bucketCount = Set(rest.compactMap { bucketKey(for: $0, level: target) }).count
        if bucketCount >= ordered.count - 1 {
            return .trade
        }
        return target
    }

    private struct Bucket {
        var key: String
        var periodStart: Date?
        var periodEnd: Date?
        var points: [ProfileStatisticsMetrics.EquityPoint]
    }

    private static func bucket(
        _ points: [ProfileStatisticsMetrics.EquityPoint],
        level: DetailLevel
    ) -> [Bucket] {
        var map: [String: Bucket] = [:]
        var order: [String] = []
        let calendar = Calendar.current

        for point in points {
            let key = bucketKey(for: point, level: level) ?? "undated-\(point.index)"
            let stamp = point.date ?? .distantPast
            if map[key] == nil {
                order.append(key)
                map[key] = Bucket(
                    key: key,
                    periodStart: periodStart(stamp, level: level, calendar: calendar),
                    periodEnd: periodEnd(stamp, level: level, calendar: calendar),
                    points: [point]
                )
            } else {
                map[key]!.points.append(point)
                map[key]!.periodEnd = periodEnd(stamp, level: level, calendar: calendar)
            }
        }

        return order.compactMap { map[$0] }
    }

    private static func tradeLevelPoints(
        _ ordered: [ProfileStatisticsMetrics.EquityPoint]
    ) -> [ScrubPoint] {
        var prior = ordered[0].equity
        return ordered.enumerated().map { offset, point in
            let net = offset == 0 ? Decimal.zero : point.equity - prior
            defer { prior = point.equity }
            return singlePoint(
                point,
                level: .trade,
                tradesInBucket: 1,
                periodNetPnL: net
            )
        }
    }

    private static func singlePoint(
        _ point: ProfileStatisticsMetrics.EquityPoint,
        level: DetailLevel,
        tradesInBucket: Int,
        periodNetPnL: Decimal = 0
    ) -> ScrubPoint {
        let date = point.date
        return ScrubPoint(
            equity: point.equity,
            drawdownFloor: point.drawdownFloor,
            anchorDate: date,
            periodStart: date,
            periodEnd: date,
            periodNetPnL: periodNetPnL,
            detailLevel: level,
            tradesInBucket: tradesInBucket
        )
    }

    private static func bucketKey(
        for point: ProfileStatisticsMetrics.EquityPoint,
        level: DetailLevel
    ) -> String? {
        guard let date = point.date else { return nil }
        let calendar = Calendar.current
        let components: DateComponents
        switch level {
        case .trade:
            return "trade-\(point.index)"
        case .day:
            components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let y = components.year, let m = components.month, let d = components.day else { return nil }
            return String(format: "d-%04d-%02d-%02d", y, m, d)
        case .week:
            components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            guard let y = components.yearForWeekOfYear, let w = components.weekOfYear else { return nil }
            return String(format: "w-%04d-%02d", y, w)
        case .month:
            components = calendar.dateComponents([.year, .month], from: date)
            guard let y = components.year, let m = components.month else { return nil }
            return String(format: "m-%04d-%02d", y, m)
        }
    }

    private static func periodStart(_ date: Date, level: DetailLevel, calendar: Calendar) -> Date {
        switch level {
        case .trade:
            return date
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        }
    }

    private static func periodEnd(_ date: Date, level: DetailLevel, calendar: Calendar) -> Date {
        switch level {
        case .trade:
            return date
        case .day:
            let start = calendar.startOfDay(for: date)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
                return calendar.date(byAdding: .second, value: -1, to: interval.end) ?? date
            }
            return date
        case .month:
            if let interval = calendar.dateInterval(of: .month, for: date) {
                return calendar.date(byAdding: .second, value: -1, to: interval.end) ?? date
            }
            return date
        }
    }

    static func scrubDateLabel(for point: ScrubPoint) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        switch point.detailLevel {
        case .trade:
            if let date = point.anchorDate {
                return formatter.string(from: date)
            }
            return "Trade"
        case .day:
            if let date = point.anchorDate {
                return formatter.string(from: date)
            }
            return "Day"
        case .week, .month:
            guard let start = point.periodStart, let end = point.periodEnd else {
                return point.detailLevel.scrubKindLabel
            }
            let short = DateFormatter()
            short.setLocalizedDateFormatFromTemplate("MMMd")
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return short.string(from: start)
            }
            return "\(short.string(from: start)) – \(short.string(from: end))"
        }
    }
}