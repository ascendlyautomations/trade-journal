import Charts
import SwiftUI

struct PropFirmSpendingBreakdownCard: View {
    let expenses: [PropFirmExpense]
    var year: Int

    @State private var mode: PropFirmSpendingBreakdownMode = .type
    @Environment(\.themeColors) private var colors

    private let donutDiameter: CGFloat = 108

    private var rows: [PropFirmExpenseBreakdown] {
        PropFirmSpendingBreakdownSupport.rows(mode: mode, expenses: expenses)
    }

    private var total: Decimal {
        rows.reduce(.zero) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                Text("Spending Breakdown")
                    .experienceStyle(.headline, color: colors.primaryText)
                AnalyticsMetricInfoButton(
                    title: "Spending Breakdown",
                    bodyText: PropFirmExpenseTrackerSectionInfo.spendingBreakdown,
                    accessibilityID: "propFirmExpenses.info.spendingBreakdown"
                )
                Spacer(minLength: 0)
            }

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
        .propFirmAnalyticsCard()
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
        ViewThatFits(in: .horizontal) {
            horizontalBreakdown
            verticalBreakdown
        }
    }

    private var horizontalBreakdown: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            donutView
            legendColumn
        }
    }

    private var verticalBreakdown: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            donutView
                .frame(maxWidth: .infinity)
            legendColumn
        }
    }

    private var donutView: some View {
        ZStack {
            Chart(rows, id: \.id) { row in
                SectorMark(
                    angle: .value("Amount", NSDecimalNumber(decimal: row.total).doubleValue),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(PropFirmSpendingBreakdownSupport.sliceColor(for: row.label))
                .cornerRadius(2)
            }
            .frame(width: donutDiameter, height: donutDiameter)
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(PropFirmExpenseMoney.compactBreakdownTotal(total))
                    .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("Total")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            .padding(.horizontal, 4)
        }
        .frame(width: donutDiameter, height: donutDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending total \(PropFirmExpenseMoney.compactBreakdownTotal(total))")
    }

    private var legendColumn: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            ForEach(rows) { row in
                legendRow(for: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(for row: PropFirmExpenseBreakdown) -> some View {
        let share = total > 0 ? (row.total / total) : 0
        let percent = NSDecimalNumber(decimal: share * 100).doubleValue

        return HStack(spacing: 6) {
            Circle()
                .fill(PropFirmSpendingBreakdownSupport.sliceColor(for: row.label))
                .frame(width: 8, height: 8)
            Text(row.label)
                .experienceStyle(.caption, color: colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(String(format: "%.0f%%", percent))
                .font(.caption.monospacedDigit())
                .foregroundStyle(colors.secondaryText)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label), \(Int(percent.rounded())) percent")
    }
}

private extension View {
    func propFirmAnalyticsCard() -> some View {
        padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
    }
}