import Foundation

enum CalendarLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum CalendarDisplayScope: String, CaseIterable, Sendable {
    case month
    case year
}

nonisolated enum CalendarPresentation {
    /// Max visible characters for the Calendar toolbar account trigger.
    static let compactAccountSelectorMaxLength = 10

    /// Truncates long account labels so the centered Calendar title is not crowded.
    static func compactAccountSelectorDisplay(_ title: String) -> String {
        let limit = compactAccountSelectorMaxLength
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)) + "…"
    }
}

/// Dynamic Y domain for Calendar year monthly P&L bars, tight padding with readable ticks.
nonisolated enum CalendarMonthlyPnLYAxisScale {
    struct Result: Equatable, Sendable {
        var lowerBound: Double
        var upperBound: Double
        var tickValues: [Double]
    }

    /// Readable major increments for monthly P&L axes.
    private static let majorSteps: [Double] = [
        50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000,
    ]

    /// Abbreviated Y-axis labels (`$1K`, `-$5K`, `$1.25M`); values under $1K stay whole dollars.
    static func formatTickLabel(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue < 0.5 { return "$0" }

        if absValue >= 1_000_000 {
            let scaled = absValue / 1_000_000
            if abs(scaled.rounded() - scaled) < 0.01 {
                return "\(sign)$\(Int(scaled.rounded()))M"
            }
            let trimmed = trimTrailingZeros(scaled)
            return "\(sign)$\(trimmed)M"
        }

        if absValue >= 1_000 {
            let scaled = absValue / 1_000
            if abs(scaled.rounded() - scaled) < 0.01 {
                return "\(sign)$\(Int(scaled.rounded()))K"
            }
            let trimmed = trimTrailingZeros(scaled)
            return "\(sign)$\(trimmed)K"
        }

        return "\(sign)$\(Int(absValue.rounded()))"
    }

    /// Builds axis bounds: ±25% padding on extrema, then ~4–5 major ticks on `majorSteps`.
    static func resolve(
        monthlyValues values: [Double],
        paddingRatio: Double = 0.25,
        targetIntervalCount: Int = 4
    ) -> Result {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else {
            return makeAxis(lower: 0, upper: 100, step: 50)
        }

        let minValue = finite.min() ?? 0
        let maxValue = finite.max() ?? 0

        if abs(minValue) < 0.01, abs(maxValue) < 0.01 {
            return makeAxis(lower: 0, upper: 100, step: 50)
        }

        let paddedUpper: Double
        let paddedLower: Double
        if minValue >= 0 {
            paddedLower = 0
            paddedUpper = maxValue > 0
                ? maxValue + abs(maxValue) * paddingRatio
                : 100
        } else if maxValue <= 0 {
            paddedUpper = 0
            paddedLower = minValue - abs(minValue) * paddingRatio
        } else {
            paddedLower = min(minValue - abs(minValue) * paddingRatio, 0)
            paddedUpper = max(maxValue + abs(maxValue) * paddingRatio, 0)
        }

        let step = chooseStep(
            paddedLower: paddedLower,
            paddedUpper: paddedUpper,
            minValue: minValue,
            maxValue: maxValue,
            targetIntervalCount: targetIntervalCount
        )

        var lower = snapDown(paddedLower, step: step)
        var upper = snapUp(paddedUpper, step: step)

        if minValue >= 0 { lower = 0 }
        if maxValue <= 0 { upper = 0 }
        if minValue < 0, maxValue > 0 {
            lower = min(lower, 0)
            upper = max(upper, 0)
        }

        if upper <= lower {
            upper = lower + step
        }

        return makeAxis(lower: lower, upper: upper, step: step)
    }

    private static func chooseStep(
        paddedLower: Double,
        paddedUpper: Double,
        minValue: Double,
        maxValue: Double,
        targetIntervalCount: Int
    ) -> Double {
        let span = max(paddedUpper - paddedLower, 1)
        let idealStep = span / Double(targetIntervalCount)

        var bestStep = majorSteps.last ?? 1_000
        var bestScore = Double.infinity

        for step in majorSteps where step >= idealStep * 0.45 {
            var lower = snapDown(paddedLower, step: step)
            var upper = snapUp(paddedUpper, step: step)
            if minValue >= 0 { lower = 0 }
            if maxValue <= 0 { upper = 0 }
            if minValue < 0, maxValue > 0 {
                lower = min(lower, 0)
                upper = max(upper, 0)
            }
            if upper <= lower { upper = lower + step }
            let intervals = Int(((upper - lower) / step).rounded()) + 1
            let intervalPenalty = abs(intervals - (targetIntervalCount + 1))
            let spanPenalty = (upper - paddedUpper) / span + (paddedLower - lower) / span
            let score = Double(intervalPenalty) * 10 + spanPenalty
            if score < bestScore {
                bestScore = score
                bestStep = step
            }
        }

        if bestScore == .infinity {
            bestStep = majorSteps.first { $0 >= idealStep } ?? majorSteps.last ?? 1_000
        }

        return bestStep
    }

    private static func makeAxis(lower: Double, upper: Double, step: Double) -> Result {
        guard step > 0, upper >= lower else {
            return Result(lowerBound: 0, upperBound: 100, tickValues: [0, 50, 100])
        }
        var ticks: [Double] = []
        var value = lower
        while value <= upper + step * 0.001 {
            ticks.append(snapToStep(value, step: step))
            value += step
        }
        if !ticks.contains(where: { abs($0) < step * 0.001 }), lower < 0, upper > 0 {
            ticks.append(0)
            ticks.sort()
        }
        return sanitizeAxisResult(
            lowerBound: lower,
            upperBound: upper,
            tickValues: ticks,
            fallbackStep: step
        )
    }

    private static func trimTrailingZeros(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.contains("."), text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private static func snapUp(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        if value >= 0 {
            return (ceil(value / step - 1e-9)) * step
        }
        return (ceil(value / step + 1e-9)) * step
    }

    private static func snapDown(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        if value <= 0 {
            return (floor(value / step + 1e-9)) * step
        }
        return (floor(value / step - 1e-9)) * step
    }

    private static func snapToStep(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Guards against non-finite bounds or empty ticks before `chartYScale(domain:)`, Swift Charts traps on invalid domains.
    private static func sanitizeAxisResult(
        lowerBound: Double,
        upperBound: Double,
        tickValues: [Double],
        fallbackStep: Double
    ) -> Result {
        let lower = lowerBound
        var upper = upperBound
        guard lower.isFinite, upper.isFinite, fallbackStep.isFinite, fallbackStep > 0 else {
            return Result(lowerBound: 0, upperBound: 100, tickValues: [0, 50, 100])
        }
        if upper <= lower {
            upper = lower + fallbackStep
        }
        var ticks = tickValues.filter(\.isFinite)
        ticks = ticks.filter { $0 >= lower - fallbackStep * 0.01 && $0 <= upper + fallbackStep * 0.01 }
        if ticks.isEmpty {
            ticks = stride(from: lower, through: upper, by: fallbackStep).map { snapToStep($0, step: fallbackStep) }
        }
        if ticks.isEmpty {
            ticks = [lower, upper]
        }
        return Result(lowerBound: lower, upperBound: upper, tickValues: ticks)
    }
}

nonisolated enum CalendarFormatting {
    /// Compact day-cell P&L (`+$842`, `-$1.2K`).
    static func compactPnL(_ value: Decimal) -> String {
        NumberDisplay.compactCurrencyAxis(value)
    }

    static func fullPnL(_ value: Decimal) -> String {
        NumberDisplay.money(value)
    }

    static func tradeCount(_ count: Int) -> String {
        NumberDisplay.tradeCount(count)
    }

    static func accessibilityLabel(for cell: CalendarGridCell) -> String {
        guard let day = cell.dayNumber else { return "Empty day" }
        let monthContext = cell.isCurrentMonth ? "" : " Outside month."
        guard let summary = cell.summary else {
            return "Day \(day). No trades.\(monthContext)"
        }
        let outcome: String
        switch summary.outcome {
        case .profit: outcome = "Profit"
        case .loss: outcome = "Loss"
        case .breakeven: outcome = "Breakeven"
        case .none: outcome = "No trades"
        }
        let amount = abs(NSDecimalNumber(decimal: summary.netPnL).doubleValue)
        return "Day \(day). \(outcome) \(Int(amount.rounded())) dollars. \(tradeCount(summary.tradeCount)).\(monthContext)"
    }
}
