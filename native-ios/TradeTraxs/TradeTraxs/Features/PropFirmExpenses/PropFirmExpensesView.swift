import SwiftUI

struct PropFirmExpensesView: View {
    @State private var viewModel: PropFirmExpensesViewModel
    @State private var firmKey = "all"
    @State private var kind: ExpenseTrackerKind?
    @State private var projectKey = "all"
    @State private var customCategory: String?
    @State private var category: PropFirmExpenseType?
    @State private var usesDateRange = false
    @State private var fromDate = Date.now
    @State private var toDate = Date.now
    @State private var editorExpense: PropFirmExpense?
    @State private var showsEditor = false
    @State private var showsIncomeEditor = false
    @State private var editingIncome: TrackerIncome?
    @State private var incomeDraft = TrackerIncomeDraft.empty()
    @State private var showsExport = false
    @State private var pendingExportURL: URL?
    @State private var exportFile: PropFirmExpenseExportFile?
    @State private var draft = PropFirmExpenseDraft.empty()
    @State private var showsCustomPercent = false
    @State private var customPercent = ""
    @State private var showsFilters = false
    @State private var showsAllIncome = false
    @State private var showsAllExpenses = false
    @State private var showsAllFirms = false

    private let historyPreviewLimit = 3

    @Environment(\.themeColors) private var colors
    @Environment(\.stackNavigation) private var stackNavigation

    init(data: DataEnvironment) {
        _viewModel = State(initialValue: PropFirmExpensesViewModel(data: data))
    }

    var body: some View {
        Group {
            if let errorMessage = viewModel.errorMessage, viewModel.expenses.isEmpty, !viewModel.isLoading {
                ExperienceErrorState(
                    title: "Couldn't load expenses",
                    message: errorMessage,
                    onRetry: { Task { await viewModel.load(force: true) } }
                )
            } else {
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Expense Tracker")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Income") {
                    editingIncome = nil
                    incomeDraft = .empty()
                    viewModel.formError = nil
                    showsIncomeEditor = true
                }
                .accessibilityIdentifier("propFirmExpenses.addIncome")
                .contextualTourTarget(.expenseTrackerIncome)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Expense") {
                    editorExpense = nil
                    draft = .empty()
                    viewModel.formError = nil
                    showsEditor = true
                }
                .accessibilityIdentifier("propFirmExpenses.add")
                .contextualTourTarget(.expenseTrackerAdd)
            }
        }
        .task { await viewModel.load() }
        .onAppear { viewModel.adoptAssignments() }
        .refreshable { await viewModel.load(force: true) }
        .sheet(isPresented: $showsEditor) {
            PropFirmExpenseEditorSheet(
                viewModel: viewModel,
                expense: editorExpense,
                accounts: viewModel.accounts,
                draft: $draft,
                isPresented: $showsEditor
            )
        }
        .sheet(isPresented: $showsIncomeEditor) {
            TrackerIncomeEditorSheet(
                viewModel: viewModel,
                income: editingIncome,
                draft: $incomeDraft,
                isPresented: $showsIncomeEditor
            )
        }
        .sheet(isPresented: $showsExport, onDismiss: {
            if let pendingExportURL {
                exportFile = PropFirmExpenseExportFile(url: pendingExportURL)
                self.pendingExportURL = nil
            }
        }) {
            PropFirmExpenseTaxExportSheet(viewModel: viewModel) { url in
                pendingExportURL = url
                showsExport = false
            }
        }
        .sheet(isPresented: $showsFilters) {
            expenseFilterSheet
        }
        .sheet(item: $exportFile) { file in
            PropFirmExpenseShareSheet(items: [file.url])
        }
    }

    private var filtered: [PropFirmExpense] {
        var fromDay: String?
        var toDay: String?
        if usesDateRange {
            let from = PropFirmExpenseMoney.dayString(from: fromDate)
            let to = PropFirmExpenseMoney.dayString(from: toDate)
            fromDay = from
            toDay = to
            if let start = fromDay, let end = toDay, start > end {
                fromDay = end
                toDay = start
            }
        }
        return PropFirmExpenseAnalyticsBuilder.filter(
            expandedExpenses,
            with: PropFirmExpenseFilter(
                firmKey: firmKey,
                category: category,
                customCategory: customCategory,
                fromDay: fromDay,
                toDay: toDay,
                kind: kind,
                projectKey: projectKey
            )
        )
    }

    private var expandedExpenses: [PropFirmExpense] {
        ExpenseRecurrenceSchedule.expand(
            viewModel.expenses,
            through: PropFirmExpenseMoney.dayString(from: .now)
        )
    }

    private var content: some View {
        let overview = viewModel.overview
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                moneySection
                incomeHistory
                history
                firmSection(overview)
                overviewSection(overview)
                spendingSection
                exportSection
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private var moneySection: some View {
        let start = String(format: "%04d-01-01", viewModel.selectedYear)
        let end = String(format: "%04d-12-31", viewModel.selectedYear)
        let expenseTotal = expandedExpenses
            .filter { $0.datePaid >= start && $0.datePaid <= end }
            .reduce(Decimal.zero) { $0 + $1.totalCost }
        let incomeRows = incomeRowsForDisplay.filter { $0.dateReceived >= start && $0.dateReceived <= end }
        let withdrawalTotal = incomeRows.filter { $0.incomeKind == .withdrawal }.reduce(Decimal.zero) { $0 + $1.amount }
        let businessTotal = incomeRows.filter { $0.incomeKind == .business }.reduce(Decimal.zero) { $0 + $1.amount }
        let incomeTotal = withdrawalTotal + businessTotal
        let net = incomeTotal - expenseTotal
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                sectionTitle("\(String(viewModel.selectedYear))")
                Spacer()
                Picker("Tax year", selection: Bindable(viewModel).selectedYear) {
                    ForEach(viewModel.taxYears(), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("propFirmExpenses.taxYear")
            }
            Text("Income and expenses. Withdrawals you already recorded are included.")
                .experienceStyle(.caption, color: colors.secondaryText)
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                metric("Income", PropFirmExpenseMoney.format(incomeTotal), tint: colors.profit)
                metric("Expenses", PropFirmExpenseMoney.format(expenseTotal), tint: colors.primaryText)
                metric("Net", PropFirmExpenseMoney.format(net), tint: net > 0 ? colors.profit : net < 0 ? colors.loss : colors.primaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Withdrawals \(PropFirmExpenseMoney.format(withdrawalTotal)) · Business income \(PropFirmExpenseMoney.format(businessTotal))")
                .experienceStyle(.subheadline, color: colors.secondaryText)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var incomeRowsForDisplay: [TrackerIncome] {
        let through = PropFirmExpenseMoney.dayString(from: .now)
        let recorded = TrackerIncomeSchedule.expand(viewModel.income, through: through)
        let withdrawals = viewModel.withdrawalItems.compactMap { item -> TrackerIncome? in
            guard item.amount > 0 else { return nil }
            let day = PropFirmExpenseMoney.utcDayString(from: item.date)
            let accountName = viewModel.accounts.first(where: { $0.id == item.accountID })?.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fromAchievement = item.source == .achievementProp || item.source == .achievementLive
            let title = item.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = (accountName?.isEmpty == false ? accountName : nil)
                ?? (fromAchievement && !title.isEmpty ? title : nil)
                ?? "Withdrawal"
            return TrackerIncome(
                id: "withdrawal:\(item.id)",
                incomeKind: .withdrawal,
                name: name,
                projectLabel: nil,
                amount: item.amount,
                dateReceived: day,
                paymentLabel: nil,
                notes: fromAchievement ? nil : item.note,
                recurrence: nil,
                seriesID: item.id,
                opensWithdrawal: true
            )
        }
        return (withdrawals + recorded).sorted { lhs, rhs in
            if lhs.dateReceived == rhs.dateReceived { return lhs.id > rhs.id }
            return lhs.dateReceived > rhs.dateReceived
        }
    }

    private var visibleIncome: [TrackerIncome] {
        incomeRowsForDisplay.filter { row in
            guard usesDateRange else { return true }
            let from = PropFirmExpenseMoney.dayString(from: fromDate)
            let to = PropFirmExpenseMoney.dayString(from: toDate)
            let start = min(from, to)
            let end = max(from, to)
            return row.dateReceived >= start && row.dateReceived <= end
        }
    }

    private var incomeHistory: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Income")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer()
                Button("Withdrawals") {
                    stackNavigation?.pushSettings(.payouts)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(colors.accent.opacity(0.9), in: Capsule())
                .accessibilityIdentifier("propFirmExpenses.withdrawals")
            }
            .padding(.horizontal, ExperienceSpacing.md)
            if visibleIncome.isEmpty {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No income yet",
                    message: "Withdrawals you already recorded show up here. Add business income for money a project receives."
                )
            } else {
                let rows = displayed(visibleIncome, expanded: showsAllIncome)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            if row.opensWithdrawal {
                                WithdrawalDetailSelection.stage(row.savedID)
                                stackNavigation?.pushSettings(.withdrawalDetail)
                                return
                            }
                            let source = viewModel.income.first { $0.id == row.savedID } ?? row
                            editingIncome = source
                            incomeDraft = .from(source)
                            viewModel.formError = nil
                            showsIncomeEditor = true
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
                .background(colors.fillSecondary.opacity(0.25), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .padding(.horizontal, ExperienceSpacing.md)
                if visibleIncome.count > historyPreviewLimit {
                    viewMoreButton(expanded: showsAllIncome) {
                        showsAllIncome.toggle()
                    }
                    .accessibilityIdentifier("propFirmExpenses.income.viewMore")
                }
            }
        }
    }

    private var spendingSection: some View {
        let rows = filtered
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionTitle("Breakdown")
                .padding(.horizontal, ExperienceSpacing.md)
            breakdown(title: "Type", rows: grouped(rows, label: { $0.trackerKind.title }), empty: "No spending yet.")
            breakdown(title: "Category", rows: grouped(rows, label: { $0.categoryTitle }), empty: "No categories yet.")
            breakdown(title: "Business or project", rows: grouped(rows, label: { $0.projectTitle }), empty: "No projects yet.")
        }
    }

    private func grouped(_ rows: [PropFirmExpense], label: (PropFirmExpense) -> String) -> [PropFirmExpenseBreakdown] {
        var buckets: [String: (String, Decimal)] = [:]
        for expense in rows {
            let name = label(expense)
            let key = name.lowercased()
            var row = buckets[key] ?? (name, .zero)
            row.1 += expense.totalCost
            buckets[key] = row
        }
        return buckets.values
            .map { PropFirmExpenseBreakdown(id: $0.0, label: $0.0, total: $0.1) }
            .sorted { $0.total == $1.total ? $0.label < $1.label : $0.total > $1.total }
    }

    private func overviewSection(_ overview: PropFirmYearOverview) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionTitle("Prop firm")
                .contextualTourTarget(.expenseTrackerAnalytics)
            Text("Payouts \(PropFirmExpenseMoney.format(overview.payouts)) · Expenses \(PropFirmExpenseMoney.format(overview.expenses)) · Net \(PropFirmExpenseMoney.format(overview.net))")
                .experienceStyle(.subheadline, color: colors.secondaryText)
            VStack(spacing: ExperienceSpacing.sm) {
                metric(
                    "Potential Tax-Deductible Expenses",
                    PropFirmExpenseMoney.format(overview.deductibleEstimate),
                    tint: colors.primaryText,
                    detail: "Unverified estimate"
                )
            }
            reserveCalculator(overview)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.sm)
    }

    private func reserveCalculator(_ overview: PropFirmYearOverview) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Estimated Tax Reserve")
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(PropFirmExpenseMoney.format(overview.reserve))
                .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            Text("Budgeting estimate on positive net payouts after expenses. This is not a tax calculation or your tax liability.")
                .experienceStyle(.caption, color: colors.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ExperienceSpacing.xs) {
                    ForEach([15, 20, 25, 30], id: \.self) { preset in
                        let selected = !showsCustomPercent && viewModel.reservePercent == Decimal(preset)
                        Button("\(preset)%") {
                            showsCustomPercent = false
                            Task { await viewModel.setReservePercent(Decimal(preset)) }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? colors.primaryText : colors.secondaryText)
                        .background(
                            selected ? colors.accent.opacity(0.85) : colors.fillSecondary.opacity(0.45),
                            in: Capsule()
                        )
                    }
                    Button("Custom") {
                        showsCustomPercent = true
                        if customPercent.isEmpty {
                            customPercent = PropFirmYearOverviewBuilder.percentLabel(viewModel.reservePercent)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(showsCustomPercent ? colors.primaryText : colors.secondaryText)
                    .background(
                        showsCustomPercent ? colors.accent.opacity(0.85) : colors.fillSecondary.opacity(0.45),
                        in: Capsule()
                    )
                }
            }
            if showsCustomPercent {
                TextField("22.5", text: $customPercent)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customPercent) { _, newValue in
                        guard let percent = PropFirmYearOverviewBuilder.parsePercent(newValue) else { return }
                        Task { await viewModel.setReservePercent(percent) }
                    }
                    .accessibilityLabel("Custom tax reserve percentage")
            }
            if let reserveError = viewModel.reserveError {
                Text(reserveError)
                    .experienceStyle(.caption, color: colors.loss)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .onChange(of: viewModel.reservePercent) { _, newValue in
            guard !PropFirmYearOverviewBuilder.isPreset(newValue) else { return }
            showsCustomPercent = true
            if PropFirmYearOverviewBuilder.parsePercent(customPercent) != newValue {
                customPercent = PropFirmYearOverviewBuilder.percentLabel(newValue)
            }
        }
    }

    private func firmSection(_ overview: PropFirmYearOverview) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionTitle("Firm Performance")
                .padding(.horizontal, ExperienceSpacing.md)
            if let best = overview.firms.first(where: { $0.key == overview.mostProfitableFirmKey }) {
                Text("Most profitable firm: \(best.label) (\(PropFirmExpenseMoney.format(best.net)) net)")
                    .experienceStyle(.subheadline, color: colors.profit)
                    .padding(.horizontal, ExperienceSpacing.md)
            } else {
                Text("No firm is attributed for \(String(overview.year)) yet.")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            }
            if overview.firms.isEmpty {
                Text("No spending or payouts in \(String(overview.year)).")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            } else {
                let firms = displayed(overview.firms, expanded: showsAllFirms)
                VStack(spacing: ExperienceSpacing.sm) {
                    ForEach(firms) { firm in
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
                            Text(firm.shortfall > 0
                                 ? "\(PropFirmExpenseMoney.format(firm.shortfall)) more in payouts to recover recorded expenses"
                                 : "Recorded expenses are recovered")
                                .experienceStyle(.caption, color: colors.primaryText)
                            if firm.key == PropFirmYearOverviewBuilder.unassignedKey {
                                Text("These payouts are not tied to one recorded prop firm.")
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                        }
                        .padding(ExperienceSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            firm.key == overview.mostProfitableFirmKey ? colors.profit.opacity(0.12) : colors.fillSecondary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                                .stroke(firm.key == overview.mostProfitableFirmKey ? colors.profit.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                if overview.firms.count > historyPreviewLimit {
                    viewMoreButton(expanded: showsAllFirms) {
                        showsAllFirms.toggle()
                    }
                    .accessibilityIdentifier("propFirmExpenses.firms.viewMore")
                }
            }
            sectionTitle("Spending Analytics")
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.xs)
            monthly(overview.months)
                .padding(.horizontal, ExperienceSpacing.md)
            breakdown(title: "Spending by Prop Firm", rows: overview.spendingByFirm, empty: "No firm spending in \(overview.year).")
            breakdown(title: "Expenses by Category", rows: overview.byCategory, empty: "No category spending in \(overview.year).")
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionTitle("Export")
            Text("Download a spreadsheet for \(String(viewModel.selectedYear)), or choose another tax year or date range. The file includes purchase dates, prop firm names, payment labels, categories, quantities, costs, payout rows, and totals for payouts, expenses, and net results.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
            Button {
                showsExport = true
            } label: {
                Text("Export Tax CSV")
                    .experienceStyle(.headline, color: colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .background(colors.profit.opacity(0.16), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                            .stroke(colors.profit.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("propFirmExpenses.export")
            .contextualTourTarget(.expenseTrackerExport)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.headline, color: colors.primaryText)
    }

    private func metric(_ title: String, _ value: String, tint: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(ExperienceSpacing.sm)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private func monthly(_ points: [PropFirmMonthComparison]) -> some View {
        let maxTotal = points.map { max($0.expenses, $0.payouts) }.max() ?? 0
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Payouts vs. Expenses")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Spacer()
                Text("Payouts")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.profit)
                Text("Expenses")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.accent)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(points) { point in
                    VStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 2) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(colors.profit.opacity(0.85))
                                .frame(width: 5, height: barHeight(point.payouts, maximum: maxTotal))
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(colors.accent.opacity(0.85))
                                .frame(width: 5, height: barHeight(point.expenses, maximum: maxTotal))
                        }
                        Text(point.label)
                            .font(.system(size: 9))
                            .foregroundStyle(colors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
    }

    private func barHeight(_ total: Decimal, maximum: Decimal) -> CGFloat {
        guard maximum > 0 else { return 4 }
        let ratio = NSDecimalNumber(decimal: total / maximum).doubleValue
        return CGFloat(Swift.max(4, ratio * 88))
    }

    private func breakdown(title: String, rows: [PropFirmExpenseBreakdown], empty: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            if rows.isEmpty {
                Text(empty)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            } else {
                let maxTotal = rows.map(\.total).max() ?? 1
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.label)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(PropFirmExpenseMoney.format(row.total))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(colors.primaryText)
                        }
                        GeometryReader { proxy in
                            let ratio = NSDecimalNumber(decimal: row.total / maxTotal).doubleValue
                            Capsule()
                                .fill(colors.accent.opacity(0.85))
                                .frame(width: max(4, proxy.size.width * ratio))
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Expense History")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer()
                Button {
                    showsFilters = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filtersAreActive ? "Filters on" : "Filter")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(colors.primaryText)
                    .background(colors.fillSecondary.opacity(0.55), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("propFirmExpenses.filter")
            }
            .padding(.horizontal, ExperienceSpacing.md)
            if viewModel.isLoading && viewModel.expenses.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if filtered.isEmpty {
                ExperienceEmptyState(
                    icon: .chart,
                    title: viewModel.expenses.isEmpty ? "No expenses yet" : "No expenses match these filters",
                    message: "Add a prop firm fee, or enter an account purchase cost when you create an eval or funded account."
                )
            } else {
                let rows = displayed(filtered, expanded: showsAllExpenses)
                VStack(spacing: 0) {
                    ForEach(rows) { expense in
                        Button {
                            let source = viewModel.expenses.first { $0.id == expense.savedID } ?? expense
                            editorExpense = source
                            draft = .from(source)
                            viewModel.formError = nil
                            showsEditor = true
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(expense.propFirmName)
                                        .experienceStyle(.body, color: colors.primaryText)
                                    Text(historySubtitle(expense))
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
                .background(colors.fillSecondary.opacity(0.25), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .padding(.horizontal, ExperienceSpacing.md)
                if filtered.count > historyPreviewLimit {
                    viewMoreButton(expanded: showsAllExpenses) {
                        showsAllExpenses.toggle()
                    }
                    .accessibilityIdentifier("propFirmExpenses.expenses.viewMore")
                }
            }
        }
    }

    private func displayed<Item>(_ items: [Item], expanded: Bool) -> [Item] {
        expanded ? items : Array(items.prefix(historyPreviewLimit))
    }

    private func viewMoreButton(expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(expanded ? "Show less" : "View more", action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ExperienceSpacing.md)
    }

    private var filtersAreActive: Bool {
        kind != nil || projectKey != "all" || firmKey != "all" || category != nil || customCategory != nil || usesDateRange
    }

    private var expenseFilterSheet: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("All types").tag(Optional<ExpenseTrackerKind>.none)
                    ForEach(ExpenseTrackerKind.allCases, id: \.self) { item in
                        Text(item.title).tag(Optional(item))
                    }
                }
                Picker("Project", selection: $projectKey) {
                    Text("All projects").tag("all")
                    ForEach(projectOptions, id: \.self) { name in
                        Text(name).tag(name.lowercased())
                    }
                }
                Picker("Name", selection: $firmKey) {
                    Text("All names").tag("all")
                    ForEach(viewModel.firmOptions(), id: \.key) { option in
                        Text(option.label).tag(option.key)
                    }
                }
                Picker("Category", selection: $category) {
                    Text("All categories").tag(Optional<PropFirmExpenseType>.none)
                    ForEach(PropFirmExpenseType.allCases, id: \.self) { type in
                        Text(type.title).tag(Optional(type))
                    }
                }
                .onChange(of: category) { _, value in
                    if value != nil { customCategory = nil }
                }
                Picker("Custom category", selection: $customCategory) {
                    Text("All custom").tag(Optional<String>.none)
                    ForEach(customCategoryOptions, id: \.self) { name in
                        Text(name).tag(Optional(name.lowercased()))
                    }
                }
                .onChange(of: customCategory) { _, value in
                    if value != nil { category = nil }
                }
                Toggle("Filter by date", isOn: $usesDateRange)
                if usesDateRange {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, displayedComponents: .date)
                }
            }
            .experienceNavigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        kind = nil
                        projectKey = "all"
                        firmKey = "all"
                        category = nil
                        customCategory = nil
                        usesDateRange = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsFilters = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var projectOptions: [String] {
        var names = Set<String>()
        for expense in viewModel.expenses {
            let label = (expense.projectLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { names.insert(label) }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var customCategoryOptions: [String] {
        var names = Set(viewModel.savedCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        for expense in viewModel.expenses {
            let label = (expense.customCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { names.insert(label) }
        }
        names.remove("")
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func historySubtitle(_ expense: PropFirmExpense) -> String {
        var parts = [expense.trackerKind.title, expense.categoryTitle]
        if let recurrence = expense.recurrence { parts.append(recurrence.title) }
        parts.append(expense.datePaid)
        if expense.quantity > 1 { parts.append("\(expense.quantity) accounts") }
        if let label = expense.paymentLabel, !label.isEmpty { parts.append(label) }
        if let accountID = expense.accountID,
           let name = viewModel.accounts.first(where: { $0.id == accountID })?.name {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }
}

private struct PropFirmExpenseExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PropFirmExpenseShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PropFirmExpenseTaxExportSheet: View {
    let viewModel: PropFirmExpensesViewModel
    var onShare: (URL) -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var usesCustomRange = false
    @State private var year: Int

    init(viewModel: PropFirmExpensesViewModel, onShare: @escaping (URL) -> Void) {
        self.viewModel = viewModel
        self.onShare = onShare
        _year = State(initialValue: viewModel.selectedYear)
    }
    @State private var fromDate = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: .now), month: 1, day: 1)) ?? .now
    @State private var toDate = Date.now
    @State private var errorMessage: String?
    @State private var kinds: Set<ExpenseTrackerKind> = [.propFirm]
    @State private var projectKey = "all"

    var body: some View {
        NavigationStack {
            Form {
                Text("This file is a financial record for the dates you choose. It lists recorded expenses and prop firm payouts, plus a summary of payouts, expenses, and net results. The deductible line is an unverified estimate. The tax reserve line is a budgeting estimate, not a tax liability.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                Section("Expense types") {
                    ForEach(ExpenseTrackerKind.allCases, id: \.self) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { kinds.contains(item) },
                            set: { enabled in
                                if enabled { kinds.insert(item) } else { kinds.remove(item) }
                            }
                        ))
                    }
                }
                Picker("Business or project", selection: $projectKey) {
                    Text("All projects").tag("all")
                    ForEach(projectNames, id: \.self) { name in
                        Text(name).tag(name.lowercased())
                    }
                }
                Picker("Reporting period", selection: $usesCustomRange) {
                    Text("Tax year").tag(false)
                    Text("Custom date range").tag(true)
                }
                if usesCustomRange {
                    DatePicker("From", selection: $fromDate, in: ...Date.now, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, in: ...Date.now, displayedComponents: .date)
                } else {
                    Picker("Tax year", selection: $year) {
                        ForEach(viewModel.taxYears(), id: \.self) { option in
                            Text(String(option)).tag(option)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                }
            }
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceNavigationTitle("Export Tax CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share CSV") { share() }
                }
            }
        }
    }

    private func share() {
        let period: (start: String, end: String)?
        if usesCustomRange {
            period = PropFirmExpenseTaxExport.customPeriod(
                from: PropFirmExpenseMoney.dayString(from: fromDate),
                to: PropFirmExpenseMoney.dayString(from: toDate)
            )
        } else {
            period = PropFirmExpenseTaxExport.yearPeriod(year)
        }
        guard let period else {
            errorMessage = "Choose a tax year, or a start date on or before the end date."
            return
        }
        guard !kinds.isEmpty else {
            errorMessage = "Choose at least one expense type."
            return
        }
        do {
            let url = try viewModel.writeTaxExport(
                periodStart: period.start,
                periodEnd: period.end,
                kinds: kinds,
                projectKey: projectKey
            )
            onShare(url)
        } catch {
            errorMessage = "Couldn't create the CSV file."
        }
    }

    private var projectNames: [String] {
        var names = Set<String>()
        for expense in viewModel.expenses {
            let label = (expense.projectLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { names.insert(label) }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct PropFirmExpenseEditorSheet: View {
    @Bindable var viewModel: PropFirmExpensesViewModel
    let expense: PropFirmExpense?
    let accounts: [TradingAccount]
    @Binding var draft: PropFirmExpenseDraft
    @Binding var isPresented: Bool
    @State private var confirmsDelete = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Form {
                Picker("Expense Type", selection: $draft.trackerKind) {
                    ForEach(ExpenseTrackerKind.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .disabled(expense?.source == .accountPurchase)
                if draft.trackerKind == .propFirm {
                    SettingsLabeledField(title: "Prop Firm Name") {
                        TextField("Apex, Topstep", text: $draft.propFirmName)
                    }
                    Picker("Prop Firm Category", selection: $draft.expenseType) {
                        ForEach(PropFirmExpenseType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                } else {
                    SettingsLabeledField(title: "Vendor or name") {
                        TextField("Vendor, tool, or expense name", text: $draft.propFirmName)
                    }
                    SettingsLabeledField(title: "Business or project") {
                        TextField("your business/project", text: $draft.projectLabel)
                    }
                    SettingsLabeledField(title: "Category") {
                        TextField("Create or choose a category", text: $draft.customCategory)
                    }
                    if !customCategoryOptions.isEmpty {
                        Picker("Saved categories", selection: Binding(
                            get: { draft.customCategory },
                            set: { draft.customCategory = $0 }
                        )) {
                            Text("Type a category").tag("")
                            ForEach(customCategoryOptions, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                SettingsLabeledField(title: draft.trackerKind == .propFirm ? "Cost Per Account" : "Amount", helper: "USD") {
                    TextField("0.00", text: $draft.costDigits.numericInput(.unsignedCurrency))
                        .keyboardType(.decimalPad)
                }
                SettingsLabeledField(title: draft.trackerKind == .propFirm ? "Quantity of Accounts" : "Quantity") {
                    TextField("1", text: $draft.quantityDigits.numericInput(.winningDays))
                        .keyboardType(.numberPad)
                }
                LabeledContent("Total Cost") {
                    Text(totalText)
                        .monospacedDigit()
                }
                DatePicker(
                    "Purchase Date",
                    selection: $draft.datePaid,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                recurrenceToggles
                SettingsLabeledField(title: "Bank/Card Paid With", helper: "Optional label only") {
                    TextField("Optional", text: $draft.paymentLabel)
                }
                SettingsLabeledField(title: "Notes", helper: "Optional") {
                    TextField("Optional", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if draft.trackerKind == .propFirm, expense?.source == .accountPurchase {
                    LabeledContent("Linked Account") {
                        Text(linkedName)
                            .foregroundStyle(colors.secondaryText)
                    }
                } else if draft.trackerKind == .propFirm {
                    Picker("Linked Account", selection: $draft.accountID) {
                        Text("None").tag(Optional<TradingAccountID>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }
                if let formError = viewModel.formError, !formError.isEmpty {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                }
            }
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceNavigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                if expense != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete", role: .destructive) { confirmsDelete = true }
                            .disabled(viewModel.isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(viewModel.isSaving)
                }
            }
            .confirmationDialog(
                "Delete this expense?",
                isPresented: $confirmsDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Expense", role: .destructive) {
                    Task { await remove() }
                }
            } message: {
                Text("This removes the expense from your history. It does not change payouts or trading P&L.")
            }
        }
    }

    private var totalText: String {
        guard let cost = PropFirmExpenseMoney.parse(draft.costDigits),
              let quantity = Int(draft.quantityDigits),
              quantity > 0
        else { return PropFirmExpenseMoney.format(0) }
        return PropFirmExpenseMoney.format(PropFirmExpenseMoney.total(cost: cost, quantity: quantity))
    }

    private var customCategoryOptions: [String] {
        var names = Set(viewModel.savedCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        for expense in viewModel.expenses {
            let label = (expense.customCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { names.insert(label) }
        }
        names.remove("")
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var recurrenceToggles: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Recurring")
                .experienceStyle(.caption, color: colors.secondaryText)
            ForEach(ExpenseRecurrence.allCases, id: \.self) { item in
                Toggle(item.title, isOn: Binding(
                    get: { draft.recurrence == item },
                    set: { draft.recurrence = $0 ? item : nil }
                ))
            }
            Text(draft.recurrence == nil
                 ? "Leave these off for a one-time amount."
                 : "Every date from the start through today is included. A future date is added when that day arrives.")
                .experienceStyle(.caption, color: colors.secondaryText)
        }
    }

    private var linkedName: String {
        guard let id = expense?.accountID else { return "Unlinked" }
        return accounts.first(where: { $0.id == id })?.name ?? "Linked account"
    }

    private func save() async {
        let ok = await viewModel.save(draft: draft, existing: expense)
        if ok { isPresented = false }
    }

    private func remove() async {
        guard let expense else { return }
        let ok = await viewModel.delete(expense)
        if ok { isPresented = false }
    }
}

private struct TrackerIncomeEditorSheet: View {
    @Bindable var viewModel: PropFirmExpensesViewModel
    let income: TrackerIncome?
    @Binding var draft: TrackerIncomeDraft
    @Binding var isPresented: Bool
    @State private var confirmsDelete = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Form {
                Picker("Income Type", selection: $draft.incomeKind) {
                    ForEach(TrackerIncomeKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Text(draft.incomeKind == .business
                     ? "Money the business or project received, such as a client payment."
                     : "Withdrawals already recorded are included. Add one here only when it is not listed there.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                SettingsLabeledField(title: draft.incomeKind == .business ? "Who paid you" : "Withdrawal from") {
                    TextField(draft.incomeKind == .business ? "Client or payer" : "Broker, firm, or account", text: $draft.name)
                }
                if draft.incomeKind == .business {
                    SettingsLabeledField(title: "Business or project") {
                        TextField("your business/project", text: $draft.projectLabel)
                    }
                }
                SettingsLabeledField(title: "Amount", helper: "USD") {
                    TextField("0.00", text: $draft.amountDigits.numericInput(.unsignedCurrency))
                        .keyboardType(.decimalPad)
                }
                DatePicker(
                    "Date Received",
                    selection: $draft.dateReceived,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                ForEach(ExpenseRecurrence.allCases, id: \.self) { item in
                    Toggle(item.title, isOn: Binding(
                        get: { draft.recurrence == item },
                        set: { draft.recurrence = $0 ? item : nil }
                    ))
                }
                Text(draft.recurrence == nil
                     ? "Leave these off for a one-time amount."
                     : "Every date from the start through today is included. A future date is added when that day arrives.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                SettingsLabeledField(title: "Bank/Card Received On", helper: "Optional label only") {
                    TextField("Optional", text: $draft.paymentLabel)
                }
                SettingsLabeledField(title: "Notes", helper: "Optional") {
                    TextField("Optional", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let formError = viewModel.formError, !formError.isEmpty {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                }
            }
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceNavigationTitle(income == nil ? "Add Income" : "Edit Income")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                if income != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete", role: .destructive) { confirmsDelete = true }
                            .disabled(viewModel.isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(viewModel.isSaving)
                }
            }
            .confirmationDialog("Delete this income?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete Income", role: .destructive) {
                    Task { await remove() }
                }
            } message: {
                Text("This removes the income and every repeated date.")
            }
        }
    }

    private func save() async {
        let ok = await viewModel.saveIncome(draft: draft, existing: income)
        if ok { isPresented = false }
    }

    private func remove() async {
        guard let income else { return }
        let ok = await viewModel.deleteIncome(income)
        if ok { isPresented = false }
    }
}
