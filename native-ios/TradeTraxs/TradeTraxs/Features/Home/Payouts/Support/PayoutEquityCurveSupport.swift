import Foundation

/// Cumulative withdrawal curve — one point per chronological payout plus a $0 origin.
nonisolated struct PayoutEquityCurvePoint: Sendable, Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var cumulative: Decimal
    var date: Date?
    /// Increment for this step — `nil` on the origin ($0) point.
    var eventAmount: Decimal?
    var source: PayoutHistoryItem.Source?

    var sourceLabel: String? {
        switch source {
        case .liveLedger: return "Live Withdrawal"
        case .otherLedger: return "Withdrawal"
        case .fundedCycle: return "Prop Payout"
        case nil: return nil
        }
    }
}

nonisolated enum PayoutEquityCurveSupport {
    static func buildPoints(from items: [PayoutHistoryItem]) -> [PayoutEquityCurvePoint] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }
        guard !sorted.isEmpty else {
            return [
                PayoutEquityCurvePoint(
                    index: 0,
                    cumulative: 0,
                    date: nil,
                    eventAmount: nil,
                    source: nil
                ),
            ]
        }

        var points: [PayoutEquityCurvePoint] = [
            PayoutEquityCurvePoint(
                index: 0,
                cumulative: 0,
                date: sorted.first?.date,
                eventAmount: nil,
                source: nil
            ),
        ]
        var running = Decimal.zero
        for (offset, item) in sorted.enumerated() {
            running += item.amount
            points.append(
                PayoutEquityCurvePoint(
                    index: offset + 1,
                    cumulative: running,
                    date: item.date,
                    eventAmount: item.amount,
                    source: item.source
                )
            )
        }
        return points
    }

    static func chartEquityPoints(from curve: [PayoutEquityCurvePoint]) -> [ProfileStatisticsMetrics.EquityPoint] {
        curve.map {
            ProfileStatisticsMetrics.EquityPoint(
                index: $0.index,
                equity: $0.cumulative,
                date: $0.date
            )
        }
    }
}
