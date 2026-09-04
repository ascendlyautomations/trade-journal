import SwiftUI

struct CalendarMonthGrid: View {
    let month: TradingCalendarMonth
    var selectedDayKey: String?
    let onSelect: (String) -> Void

    @Environment(\.themeColors) private var colors

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(.caption2, design: .default).weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            let rowCount = month.cells.count / 7
            ForEach(0..<rowCount, id: \.self) { row in
                VStack(spacing: 2) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(month.cells[(row * 7)..<((row + 1) * 7)]) { cell in
                            CalendarDayCell(
                                cell: cell,
                                isSelected: cell.dayKey == selectedDayKey
                            ) {
                                if let key = cell.dayKey, cell.isCurrentMonth {
                                    onSelect(key)
                                }
                            }
                        }
                    }
                    if row < month.weekSummaries.count {
                        let week = month.weekSummaries[row]
                        if week.tradingDayCount > 0 {
                            CalendarWeekSummaryIndicator(netPnL: week.netPnL)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("calendar.grid")
    }
}
