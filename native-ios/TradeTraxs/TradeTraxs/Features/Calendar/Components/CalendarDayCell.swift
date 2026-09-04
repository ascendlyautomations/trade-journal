import SwiftUI

struct CalendarDayCell: View {
    let cell: CalendarGridCell
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(cell.dayNumber.map(String.init) ?? "")
                    .font(.system(.caption2, design: .default).weight(cell.isToday ? .bold : .medium))
                    .foregroundStyle(dayNumberColor)

                if let summary = cell.summary, cell.isCurrentMonth {
                    Text(CalendarFormatting.compactPnL(summary.netPnL))
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(pnlColor(for: summary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if summary.tradeCount > 0 {
                        Text(compactTradeCount(summary.tradeCount))
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 4)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected || cell.isToday ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(cell.dayNumber == nil)
        .opacity(cell.isCurrentMonth ? 1 : 0.35)
        .accessibilityLabel(CalendarFormatting.accessibilityLabel(for: cell))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(cell.dayKey.map { "calendar.day.\($0)" } ?? "calendar.day.empty")
    }

    private func compactTradeCount(_ count: Int) -> String {
        count == 1 ? "1 tr" : "\(count) tr"
    }

    private var dayNumberColor: Color {
        if !cell.isCurrentMonth { return colors.tertiaryText }
        if cell.isToday { return colors.primaryText }
        return colors.secondaryText
    }

    private func pnlColor(for summary: TradingDaySummary) -> Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: summary.netPnL).doubleValue
        )
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            .fill(fillColor)
    }

    private var fillColor: Color {
        guard cell.isCurrentMonth, let summary = cell.summary else {
            return colors.fillTertiary.opacity(0.35)
        }
        switch summary.outcome {
        case .profit:
            return colors.profit.opacity(0.12)
        case .loss:
            return colors.loss.opacity(0.12)
        case .breakeven:
            return colors.neutralMetric.opacity(0.12)
        case .none:
            return colors.fillTertiary.opacity(0.35)
        }
    }

    private var borderColor: Color {
        if isSelected { return colors.accent }
        if cell.isToday { return colors.accent.opacity(0.6) }
        return .clear
    }
}
