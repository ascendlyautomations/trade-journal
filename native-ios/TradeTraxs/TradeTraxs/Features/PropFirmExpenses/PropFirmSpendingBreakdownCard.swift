import Charts
import SwiftUI

struct PropFirmSpendingBreakdownCard: View {
    let expenses: [PropFirmExpense]
    var year: Int

    @State private var mode: PropFirmSpendingBreakdownMode = .type
    @Environment(\.themeColors) private var colors

    private var rows: [PropFirmExpenseBreakdown] {
        PropFirmSpendingBreakdownSupport.rows(mode: mode, expenses: expenses)
    }

    private var total: Decimal {
        rows.reduce(.zero) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Spending Breakdown")
                .experienceStyle(.headline, color: colors.primaryText)

            Picker("Breakdown", selection: $mode) {
                ForEach(PropFirmSpendingBreakdownMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("propFirmExpenses.breakdown.mode")

            if rows.isEmpty {
                Text(emptyMessage)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ExperienceSpacing.sm)
            } else {
                donutAndLegend
            }
        }
        .propFirmAnalyticsCard(colors: colors)
    }

    private var emptyMessage: String {
        switch mode {
        case .business:
            return "No business expenses recorded in \(year)."
        default:
            return "No spending recorded in \(year)."
        }
    }

    private var donutAndLegend: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                ZStack {
                    Chart(Array(rows.enumerated()), id: \.element.id) { index, row in
                        SectorMark(
                            angle: .value("Amount", NSDecimalNumber(decimal: row.total).doubleValue),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(PropFirmSpendingBreakdownSupport.sliceColor(index: index, colors: colors))
                        .cornerRadius(2)
                    }
                    .frame(width: 116, height: 116)
                    .accessibilityHidden(true)

                    VStack(spacing: 2) {
                        Text(PropFirmExpenseMoney.format(total))
                            .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text("Total")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let share = total > 0 ? (row.total / total) : 0
                    let percent = NSDecimalNumber(decimal: share * 100).doubleValue
                    HStack(spacing: ExperienceSpacing.sm) {
                        Circle()
                            .fill(PropFirmSpendingBreakdownSupport.sliceColor(index: index, colors: colors))
                            .frame(width: 8, height: 8)
                        Text(row.label)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: ExperienceSpacing.xs)
                        Text(PropFirmExpenseMoney.format(row.total))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                        Text(String(format: "%.0f%%", percent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(colors.secondaryText)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private extension View {
    func propFirmAnalyticsCard(colors: SemanticColorPalette) -> some View {
        padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: ExperienceBorder.hairline)
            )
    }
}