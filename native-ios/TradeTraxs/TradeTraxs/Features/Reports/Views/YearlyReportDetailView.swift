import SwiftUI

struct YearlyReportDetailView: View {
    @State private var viewModel: YearlyReportDetailViewModel

    @Environment(\.themeColors) private var colors

    init(
        year: Int,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: YearlyReportDetailViewModel(
                year: year,
                tradingReports: data.tradingReports,
                trades: data.trades,
                session: data.session,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                loadingContent
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't open report",
                    message: message,
                    onRetry: { Task { await viewModel.retry() } }
                )
            case .loaded:
                detailScroll
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(viewModel.title)
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.bootstrapIfNeeded() }
        .accessibilityIdentifier("reports.yearly.detail")
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                YearlyReportFilterBar(viewModel: viewModel)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                if let report = viewModel.report {
                    yearlyHeader(report: report)
                        .padding(.horizontal, ExperienceSpacing.md)

                    YearlyReportSummaryMetricsView(metrics: report.metrics)
                        .padding(.horizontal, ExperienceSpacing.md)

                    YearlyReportChartsSection(report: report)
                        .padding(.horizontal, ExperienceSpacing.md)

                    YearlyReportMonthBreakdownView(
                        rows: report.monthRows,
                        onOpenMonth: { viewModel.openMonth($0) }
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private func yearlyHeader(report: TradingYearlyReport) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Yearly Performance Report")
                .experienceStyle(.caption2, color: colors.accent)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(report.dateRangeLabel)
                .experienceStyle(.subheadline, color: colors.secondaryText)

            Text(report.executiveSummary)
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.14),
                            colors.fillSecondary.opacity(0.6),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var loadingContent: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            ProgressView("Generating report…")
                .tint(colors.accent)
                .padding(.top, ExperienceSpacing.xxl)
            ExperienceSkeleton(height: 110, cornerRadius: ExperienceRadius.card)
            ForEach(0..<4, id: \.self) { _ in
                ExperienceSkeleton(height: 128, cornerRadius: ExperienceRadius.card)
            }
            Spacer()
        }
        .padding(ExperienceSpacing.md)
    }
}

struct YearlyReportFilterBar: View {
    @Bindable var viewModel: YearlyReportDetailViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                OwnerAccountFilterDropdown(
                    accounts: viewModel.accountsForMenu,
                    isAllAccountsSelected: {
                        if case .all = viewModel.filters.accountFilter { return true }
                        return false
                    }(),
                    selectedAccountID: {
                        if case .account(let id) = viewModel.filters.accountFilter { return id }
                        return nil
                    }(),
                    onSelectAll: { viewModel.setAccountFilter(.all) },
                    onSelectAccount: { viewModel.setAccountFilter(.account($0)) },
                    onManageAccounts: { viewModel.openManageAccounts() },
                    accessibilityIdentifier: "reports.yearly.account",
                    profileID: viewModel.ownerProfileID
                ) {
                    HStack(spacing: 4) {
                        Text(viewModel.accountFilterTitle)
                            .experienceStyle(.footnote, color: colors.accent)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.accent)
                    }
                }

                modeMenu
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("reports.yearly.filters")
    }

    private var modeMenu: some View {
        Menu {
            ForEach(ProfileStatisticsMetrics.Mode.profileFilterCases) { mode in
                Button {
                    viewModel.setAccountMode(mode)
                } label: {
                    if viewModel.filters.accountMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.filters.accountMode.title)
                    .experienceStyle(.footnote, color: colors.accent)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.accent)
            }
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        }
        .accessibilityIdentifier("reports.yearly.mode")
    }
}

struct YearlyReportSummaryMetricsView: View {
    let metrics: TradingYearlyReportMetrics

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Year Summary")
                .experienceStyle(.headline, color: colors.primaryText)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                    GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                ],
                spacing: ExperienceSpacing.sm
            ) {
                metricCell("Net P&L", formatMoney(metrics.netPnl), tone: pnlTone(metrics.netPnl))
                metricCell("Total Trades", "\(metrics.tradeCount)")
                metricCell("Win Rate", formatWinRate(metrics.winRate))
                metricCell("Profit Factor", formatOptionalDecimal(metrics.profitFactor))
                metricCell("Average Winner", formatOptionalMoney(metrics.averageWinner))
                metricCell("Average Loser", formatOptionalMoney(metrics.averageLoser))
                metricCell("Average RR", formatOptionalDecimal(metrics.averageRR))
                metricCell("Expectancy", formatOptionalMoney(metrics.expectancy))
                metricCell("Best Trade", formatOptionalMoney(metrics.bestTrade))
                metricCell("Worst Trade", formatOptionalMoney(metrics.worstTrade))
                metricCell(
                    "Best Day",
                    metrics.bestDayLabel.map { "\($0) (\(formatMoney(metrics.bestDayPnl ?? 0)))" } ?? "—"
                )
                metricCell(
                    "Worst Day",
                    metrics.worstDayLabel.map { "\($0) (\(formatMoney(metrics.worstDayPnl ?? 0)))" } ?? "—"
                )
                metricCell("Max Drawdown", formatMoney(metrics.maxDrawdown))
                metricCell("Winning Days", "\(metrics.winningDays)")
                metricCell("Losing Days", "\(metrics.losingDays)")
            }
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityIdentifier("reports.yearly.summary")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
            .fill(colors.fillSecondary.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.thin)
            }
    }

    private func metricCell(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tone ?? colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary.opacity(0.65), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
    }

    private func pnlTone(_ value: Decimal) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.primaryText
    }

    private func formatMoney(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let absValue = abs(number)
        let formatted = absValue.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
        return number < 0 ? "-$\(formatted)" : "$\(formatted)"
    }

    private func formatOptionalMoney(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return formatMoney(value)
    }

    private func formatOptionalDecimal(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func formatWinRate(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", NSDecimalNumber(decimal: value * 100).doubleValue)
    }
}

struct YearlyReportChartsSection: View {
    let report: TradingYearlyReport

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            chartCard(title: "Cumulative P&L") {
                if report.chartSummary.equityData.isEmpty {
                    DashboardChartEmptyCopy(message: "Log trades this year to unlock your equity curve.")
                } else {
                    ProfileEquityCurveView(points: report.chartSummary.equityData)
                        .frame(height: 220)
                }
            }

            chartCard(title: "Monthly P&L") {
                YearlyMonthlyPnLBarsView(points: report.monthlyPnLBars)
            }

            chartCard(title: "Win / Loss") {
                DashboardWinLossRingView(
                    winCount: report.chartSummary.winCount,
                    lossCount: report.chartSummary.lossCount
                )
            }

            if report.strongestMonth != nil || report.weakestMonth != nil {
                chartCard(title: "Strongest / Weakest Month") {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        if let strongest = report.strongestMonth {
                            monthHighlightRow(
                                title: "Strongest",
                                month: strongest.monthLabel,
                                pnl: strongest.netPnl,
                                tone: colors.profit
                            )
                        }
                        if let weakest = report.weakestMonth {
                            monthHighlightRow(
                                title: "Weakest",
                                month: weakest.monthLabel,
                                pnl: weakest.netPnl,
                                tone: colors.loss
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("reports.yearly.charts")
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            content()
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(colors.fillSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                        .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.thin)
                }
        }
    }

    private func monthHighlightRow(title: String, month: String, pnl: Decimal, tone: Color) -> some View {
        HStack {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(month)
                .experienceStyle(.subheadline, color: colors.primaryText)
            Spacer()
            Text(formatMoney(pnl))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tone)
        }
        .padding(ExperienceSpacing.sm)
        .background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
    }

    private func formatMoney(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let absValue = abs(number)
        let formatted = absValue.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
        return number < 0 ? "-$\(formatted)" : "$\(formatted)"
    }
}

struct YearlyMonthlyPnLBarsView: View {
    let points: [DashboardBarPoint]

    @Environment(\.themeColors) private var colors

    private var maxAbs: Double {
        max(points.map { abs($0.value) }.max() ?? 0, 1)
    }

    var body: some View {
        if points.isEmpty {
            DashboardChartEmptyCopy(message: "Monthly P&L appears once you have closed trades this year.")
        } else {
            HStack(alignment: .bottom, spacing: ExperienceSpacing.xs) {
                ForEach(points) { point in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(point.value >= 0 ? colors.profit : colors.loss)
                            .frame(
                                height: max(6, CGFloat(abs(point.value) / maxAbs) * 88)
                            )
                        Text(point.label)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(point.label), \(point.value)")
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
    }
}

struct YearlyReportMonthBreakdownView: View {
    let rows: [TradingYearlyMonthRow]
    var onOpenMonth: (TradingReportMonthRef) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Monthly Breakdown")
                .experienceStyle(.headline, color: colors.primaryText)

            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(rows) { row in
                    monthRow(row)
                }
            }
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(colors.fillSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                        .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.thin)
                }
        }
        .accessibilityIdentifier("reports.yearly.months")
    }

    @ViewBuilder
    private func monthRow(_ row: TradingYearlyMonthRow) -> some View {
        switch row.availability {
        case .upcoming:
            HStack {
                Text(row.monthLabel)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                Spacer()
                Text("Upcoming")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            .padding(ExperienceSpacing.sm)
            .background(colors.backgroundSecondary.opacity(0.35), in: RoundedRectangle(
                cornerRadius: ExperienceRadius.sm,
                style: .continuous
            ))

        case .available(let metrics):
            Button {
                onOpenMonth(metrics.monthRef)
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    Text(row.monthLabel)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .frame(width: 96, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatMoney(metrics.netPnl))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(pnlColor(metrics.netPnl))
                        Text("\(metrics.tradeCount) trades · \(formatWinRate(metrics.winRate)) WR")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    Spacer()
                    ExperienceIcon(icon: .forward, size: .xs, color: colors.tertiaryText)
                }
                .padding(ExperienceSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(colors.backgroundSecondary.opacity(0.65), in: RoundedRectangle(
                cornerRadius: ExperienceRadius.sm,
                style: .continuous
            ))
            .accessibilityIdentifier("reports.yearly.month.\(row.month)")
        }
    }

    private func pnlColor(_ value: Decimal) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.primaryText
    }

    private func formatMoney(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let absValue = abs(number)
        let formatted = absValue.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
        return number < 0 ? "-$\(formatted)" : "$\(formatted)"
    }

    private func formatWinRate(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", NSDecimalNumber(decimal: value * 100).doubleValue)
    }
}
