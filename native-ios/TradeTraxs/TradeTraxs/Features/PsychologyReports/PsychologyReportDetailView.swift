import SwiftUI

struct PsychologyReportDetailView: View {
    @State private var viewModel: PsychologyReportDetailViewModel

    @Environment(\.themeColors) private var colors

    private let condensedBulletLimit = 3

    init(reportID: ReportID, data: DataEnvironment) {
        _viewModel = State(
            initialValue: PsychologyReportDetailViewModel(
                reportID: reportID,
                psychologyReports: data.psychologyReports
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ExperienceLoadingSpinner(message: "Loading report…")
            case .failed(let message):
                ExperienceErrorState(title: "Couldn't open report", message: message) {
                    Task { await viewModel.bootstrapIfNeeded() }
                }
            case .loaded:
                if let report = viewModel.report {
                    reportScroll(report)
                }
            }
        }
        .experienceScreenBackground()
        .modifier(PsychologyReportNavigationChrome(viewModel: viewModel))
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.bootstrapIfNeeded()
        }
        .sheet(isPresented: $viewModel.showsCustomDateSheet) {
            PsychologyReportCustomDateRangeSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("psychologyReport.detail")
    }

    private func reportScroll(_ report: PsychologyReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ReportDetailLayout.sectionSpacing) {
                PsychologyReportCoverageCard(report: report)
                    .padding(.top, ReportDetailLayout.headerToFirstSectionSpacing)

                if let insight = PsychologyReportChartPlanner.primaryInsight(for: report) {
                    PsychologyReportPrimaryInsightCard(card: insight)
                }

                PsychologyReportChartsSection(report: report)

                let strengths = Array(report.doingWell.prefix(condensedBulletLimit))
                if !strengths.isEmpty {
                    PsychologyReportBulletStrip(
                        title: "What Went Well",
                        items: strengths,
                        tint: colors.success
                    )
                }

                let watch = Array(report.watchItems.prefix(condensedBulletLimit))
                if !watch.isEmpty {
                    PsychologyReportBulletStrip(
                        title: "What to Watch",
                        items: watch,
                        tint: colors.warning
                    )
                }

                PsychologyReportPerformanceMetricsCard(report: report)

                ComplianceDisclaimerFootnote(text: ComplianceDisclaimerCopy.performanceReport)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

private struct PsychologyReportNavigationChrome: ViewModifier {
    @Bindable var viewModel: PsychologyReportDetailViewModel

    func body(content: Content) -> some View {
        if let periodLabel = viewModel.navigationPeriodLabel {
            content.modifier(
                ReportDetailPerformanceNavigationChrome(
                    periodLabel: periodLabel,
                    fallbackTitle: viewModel.title
                )
            )
        } else {
            content
                .experienceNavigationTitle(viewModel.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if viewModel.supportsDateScope {
                            PsychologyReportDateScopeToolbarMenu(viewModel: viewModel)
                        }
                    }
                }
        }
    }
}