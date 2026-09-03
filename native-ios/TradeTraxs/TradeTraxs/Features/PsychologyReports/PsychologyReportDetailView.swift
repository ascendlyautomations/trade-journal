import SwiftUI

struct PsychologyReportDetailView: View {
    @State private var viewModel: PsychologyReportDetailViewModel

    @Environment(\.themeColors) private var colors

    init(reportID: ReportID, data: DataEnvironment) {
        _viewModel = State(
            initialValue: PsychologyReportDetailViewModel(
                reportID: reportID,
                psychologyReports: data.psychologyReports,
                ai: data.ai
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ProgressView("Loading report…")
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
        .experienceNavigationTitle(viewModel.title)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.bootstrapIfNeeded()
            await viewModel.loadAISummaryIfNeeded()
        }
        .accessibilityIdentifier("psychologyReport.detail")
    }

    private func reportScroll(_ report: PsychologyReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                header(report)

                if let ai = viewModel.aiSummary {
                    aiSummarySection(ai)
                } else if viewModel.isLoadingAI {
                    ProgressView("Generating AI summary…")
                        .frame(maxWidth: .infinity)
                }

                if !report.doingWell.isEmpty {
                    bulletSection(title: "What Went Well", items: report.doingWell, tint: colors.success)
                }

                ForEach(report.sections) { section in
                    sectionCard(section)
                }

                if !report.watchItems.isEmpty {
                    bulletSection(title: "What to Watch", items: report.watchItems, tint: colors.warning)
                }

                if !report.comparisons.isEmpty {
                    comparisonsSection(report.comparisons)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private func header(_ report: PsychologyReport) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Psychology Report")
                .experienceStyle(.caption2, color: colors.accent)
                .textCase(.uppercase)
            Text(report.dateRangeLabel)
                .experienceStyle(.subheadline, color: colors.secondaryText)
            Text("Deterministic insights from your journal")
                .experienceStyle(.footnote, color: colors.tertiaryText)
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card))
    }

    private func aiSummarySection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("AI Psychology Summary")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(text)
                .experienceStyle(.body, color: colors.secondaryText)
            Text("Numbers above come from TradeTraxs analytics — AI explains supported patterns only.")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
        .background(colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }

    private func sectionCard(_ section: PsychologyReportSection) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(section.title)
                .experienceStyle(.headline, color: colors.primaryText)
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .experienceStyle(.footnote, color: colors.tertiaryText)
            }
            if !section.metrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ExperienceSpacing.sm) {
                    ForEach(section.metrics, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                            Text(row.value)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(colors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ForEach(section.bullets, id: \.self) { bullet in
                Text("• \(bullet)")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
    }

    private func bulletSection(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 6)
                    Text(item).experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }

    private func comparisonsSection(_ comparisons: [PsychologyReportComparison]) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Period Comparisons")
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(comparisons, id: \.headline) { comparison in
                VStack(alignment: .leading, spacing: 4) {
                    Text(comparison.headline)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Text(comparison.detail)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }
}
