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
