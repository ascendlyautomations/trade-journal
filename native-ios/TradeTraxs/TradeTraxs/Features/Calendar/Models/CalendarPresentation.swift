import Foundation

enum CalendarLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

nonisolated enum CalendarFormatting {
    /// Compact day-cell P&L (`+$842`, `-$1.2K`).
    static func compactPnL(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let sign = number < 0 ? "-" : "+"
        let absValue = abs(number)
        if absValue >= 10_000 {
            return "\(sign)$\(String(format: "%.1f", absValue / 1_000))K"
        }
        if absValue >= 1_000 {
            let k = absValue / 1_000
            if k.rounded() == k {
                return "\(sign)$\(Int(k))K"
            }
            return "\(sign)$\(String(format: "%.1f", k))K"
        }
        return "\(sign)$\(Int(absValue.rounded()))"
    }

    static func fullPnL(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let absAmount = abs(value)
        let body = formatter.string(from: NSDecimalNumber(decimal: absAmount)) ?? "\(absAmount)"
        return value < 0 ? "-$\(body)" : "$\(body)"
    }

    static func tradeCount(_ count: Int) -> String {
        count == 1 ? "1 trade" : "\(count) trades"
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
