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
        .modifier(
            ReportDetailPerformanceNavigationChrome(
                periodLabel: viewModel.navigationPeriodLabel,
                fallbackTitle: viewModel.title
            )
        )
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.bootstrapIfNeeded() }
        .onOwnerAccountMutation { viewModel.handleAccountMutation(detailCache: nil) }
        .accessibilityIdentifier("reports.yearly.detail")
    }

    private var detailScroll: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                YearlyReportFilterBar(viewModel: viewModel)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                if let report = viewModel.report {
                    if !report.executiveSummary.isEmpty {
                        Text(report.executiveSummary)
                            .experienceStyle(.footnote, color: colors.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, ExperienceSpacing.md)
                            .padding(.top, ExperienceSpacing.xs)
                            .accessibilityIdentifier("reports.yearly.executiveSummary")
                    }

                    YearlyReportSummaryMetricsView(metrics: report.metrics)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ReportDetailLayout.headerToFirstSectionSpacing)

                    YearlyReportChartsSection(report: report)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ReportDetailLayout.sectionSpacing)

                    YearlyReportMonthBreakdownView(
                        rows: report.monthRows,
                        onOpenMonth: { viewModel.openMonth($0) }
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ReportDetailLayout.sectionSpacing)

                    ComplianceDisclaimerFootnote(text: ComplianceDisclaimerCopy.performanceReport)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.top, ReportDetailLayout.sectionSpacing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    private var loadingContent: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            ExperienceLoadingSpinner(message: "Generating report…")
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
        ProposedWidthClamp {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                OwnerAccountFilterDropdown(
                    accounts: viewModel.accountsForMenu,
                    selectedFilter: viewModel.filters.accountFilter,
                    copyGroups: OwnerAccountFilterMenuSupport.copyGroups(for: viewModel.ownerProfileID),
                    isLoadingCopyGroups: OwnerAccountFilterMenuSupport.isLoadingCopyGroups(
                        for: viewModel.ownerProfileID
                    ),
                    onSelectFilter: { viewModel.setAccountFilter($0) },
                    onManageAccounts: { viewModel.openManageAccounts() },
                    onManageCopyGroups: { viewModel.openManageCopyTradingGroups() },
                    onRequestCopyGroups: {
                        OwnerAccountFilterMenuSupport.requestCopyGroupsLoad(profileID: viewModel.ownerProfileID)
                    },
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .experienceControlHitTarget()
        }
        .accessibilityIdentifier("reports.yearly.mode")
    }
}

struct YearlyReportSummaryMetricsView: View {
    let metrics: TradingReportMetrics

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Key Metrics")
                .experienceStyle(.headline, color: colors.primaryText)

            ReportKeyMetricsGrid(metrics: metrics)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ReportDetailSectionSurface())
        .accessibilityIdentifier("reports.yearly.summary")
    }
}

struct YearlyReportChartsSection: View {
    let report: TradingYearlyReport

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ReportDetailLayout.sectionSpacing) {
            chartCard(title: "Cumulative P&L") {
                if report.chartSummary.equityData.isEmpty {
                    DashboardChartEmptyCopy(message: "Log trades this year to unlock your equity curve.")
                } else {
                    ProfileEquityCurveView(points: report.chartSummary.equityData)
                        .frame(maxWidth: .infinity)
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
            ProposedWidthClamp {
                content()
            }
            .clipped()
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ReportDetailSectionSurface())
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
        NumberDisplay.currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
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
            ProposedWidthClamp {
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
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(point.label), \(NumberDisplay.reportPnL(point.value))")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120, alignment: .bottom)
            }
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
        .modifier(ReportDetailSectionSurface())
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
                        Text("\(NumberDisplay.integer(metrics.tradeCount)) trades · \(formatWinRate(metrics.winRate)) WR")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    Spacer()
                    ExperienceIcon(icon: .forward, size: .xs, color: colors.tertiaryText)
                }
                .padding(ExperienceSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)
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
        NumberDisplay.currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    private func formatWinRate(_ value: Decimal?) -> String {
        guard let value else { return "–" }
        return NumberDisplay.percent(value * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)
    }
}
