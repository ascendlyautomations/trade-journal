import SwiftUI

struct PropFirmFirmPerformanceListView: View {
    let overview: PropFirmYearOverview
    var mostProfitableKey: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if overview.firms.isEmpty {
                    ExperienceEmptyState(
                        icon: .chart,
                        title: "No firm performance",
                        message: "No spending or payouts in \(overview.year)."
                    )
                } else {
                    ForEach(overview.firms) { firm in
                        PropFirmPerformanceCard(
                            firm: firm,
                            highlighted: firm.key == mostProfitableKey
                        )
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Firm Performance")
    }
}

struct PropFirmPerformanceCard: View {
    let firm: PropFirmProfitability
    var highlighted: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(firm.label)
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer()
                Text("\(PropFirmExpenseMoney.format(firm.net)) net")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(firm.net > 0 ? colors.profit : firm.net < 0 ? colors.loss : colors.primaryText)
            }
            Text("Spent \(PropFirmExpenseMoney.format(firm.spent)) · Payouts \(PropFirmExpenseMoney.format(firm.payouts))")
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(
                firm.shortfall > 0
                    ? "\(PropFirmExpenseMoney.format(firm.shortfall)) more in payouts to recover recorded expenses"
                    : "Recorded expenses are recovered"
            )
            .experienceStyle(.caption, color: colors.primaryText)
            if firm.key == PropFirmYearOverviewBuilder.unassignedKey {
                Text("These payouts are not tied to one recorded prop firm.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PropFirmPerformanceCardSurface(highlighted: highlighted))
    }
}

struct PropFirmIncomeHistoryListView: View {
    let rows: [TrackerIncome]
    var onSelect: (TrackerIncome) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if rows.isEmpty {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No income yet",
                    message: "Add business income for client or project payments."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button {
                                onSelect(row)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .experienceStyle(.body, color: colors.primaryText)
                                        Text(row.subtitle)
                                            .experienceStyle(.caption, color: colors.secondaryText)
                                    }
                                    Spacer()
                                    Text(PropFirmExpenseMoney.format(row.amount))
                                        .font(.body.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(colors.profit)
                                }
                                .padding(.horizontal, ExperienceSpacing.md)
                                .padding(.vertical, ExperienceSpacing.sm)
                            }
                            .buttonStyle(.plain)
                            if row.id != rows.last?.id {
                                Divider().padding(.leading, ExperienceSpacing.md)
                            }
                        }
                    }
                    .modifier(ReportDetailInsetSurface(cornerRadius: ExperienceRadius.md))
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xxxl)
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Income History")
    }
}

struct PropFirmExpenseHistoryListView: View {
    let rows: [PropFirmExpense]
    var subtitle: (PropFirmExpense) -> String
    var onSelect: (PropFirmExpense) -> Void
    var showsFilterAction: (() -> Void)?
    var filtersActive: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if rows.isEmpty {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No expenses",
                    message: "No expenses match the current filters."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { expense in
                            Button {
                                onSelect(expense)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(expense.propFirmName)
                                            .experienceStyle(.body, color: colors.primaryText)
                                        Text(subtitle(expense))
                                            .experienceStyle(.caption, color: colors.secondaryText)
                                    }
                                    Spacer()
                                    Text(PropFirmExpenseMoney.format(expense.totalCost))
                                        .font(.body.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(colors.primaryText)
                                }
                                .padding(.horizontal, ExperienceSpacing.md)
                                .padding(.vertical, ExperienceSpacing.sm)
                            }
                            .buttonStyle(.plain)
                            if expense.id != rows.last?.id {
                                Divider().padding(.leading, ExperienceSpacing.md)
                            }
                        }
                    }
                    .modifier(ReportDetailInsetSurface(cornerRadius: ExperienceRadius.md))
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xxxl)
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Expense History")
        .toolbar {
            if let showsFilterAction {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: showsFilterAction) {
                        Label(filtersActive ? "Filters on" : "Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

private struct PropFirmPerformanceCardSurface: ViewModifier {
    var highlighted: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if highlighted {
            content
                .background(colors.profit.opacity(0.12), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                        .stroke(colors.profit.opacity(0.55), lineWidth: ExperienceBorder.hairline)
                }
        } else if colorScheme == .light {
            content.experienceDashboardNestedCard(cornerRadius: ExperienceRadius.md)
        } else {
            content
                .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                        .stroke(colors.border.opacity(0.22), lineWidth: 1)
                }
        }
    }
}