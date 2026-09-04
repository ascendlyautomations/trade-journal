import SwiftUI

/// Reports catalog — Performance Reports + Psychology Reports.
struct ReportsScreenView: View {
    @State private var viewModel: ReportsScreenViewModel
    @State private var isPerformanceExpanded = false
    @State private var isPsychologyExpanded = false

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: ReportsScreenViewModel(
                tradingReports: data.tradingReports,
                psychologyReports: data.psychologyReports,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    init(viewModel: ReportsScreenViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .failed(let message) where viewModel.cards.allSatisfy({ $0.availability != .ready })
                && viewModel.psychologyCards.allSatisfy({ $0.availability != .ready }):
                ExperienceErrorState(
                    title: "Couldn't load Reports",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            default:
                catalogScroll
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Reports")
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.bootstrapIfNeeded() }
        .sheet(isPresented: $viewModel.showsPeriodPicker) {
            PsychologyReportPeriodPickerView(
                periods: viewModel.periodPickerPeriods,
                onSelect: { viewModel.openPsychologyPeriod($0) },
                onClose: { viewModel.showsPeriodPicker = false }
            )
            .experienceSheetChrome()
        }
        .sheet(isPresented: $viewModel.showsYearPicker) {
            TradingReportYearPickerView(
                years: viewModel.availableYears,
                onSelect: { viewModel.openYearlyReport(year: $0) },
                onClose: { viewModel.showsYearPicker = false }
            )
            .experienceSheetChrome()
        }
        .accessibilityIdentifier("reports.home")
    }

    private var catalogScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                intro
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                performanceSection
                psychologySection
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isPerformanceExpanded
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isPsychologyExpanded
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.cards.map(\.actionTitle)
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Your Reports")
                .experienceStyle(.title3, color: colors.primaryText)
            Text("Performance reviews and psychology insights from your journal.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ReportsSectionHeader(
                title: "Performance Reports",
                subtitle: "Trading performance and account reports",
                isExpanded: isPerformanceExpanded,
                onToggle: { togglePerformanceSection() }
            )
            .accessibilityIdentifier("reports.section.performance")

            if isPerformanceExpanded {
                ForEach(viewModel.cards) { card in
                    performanceCard(card)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let yearlyCard = viewModel.yearlyCard {
                    yearlyCardView(yearlyCard)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var psychologySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ReportsSectionHeader(
                title: "Psychology Reports",
                subtitle: "Behavior, discipline and psychology reports",
                isExpanded: isPsychologyExpanded,
                onToggle: { togglePsychologySection() }
            )
            .accessibilityIdentifier("reports.section.psychology")

            if isPsychologyExpanded {
                ForEach(viewModel.psychologyCards) { card in
                    psychologyCard(card)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func performanceCard(_ card: ReportTypeCardModel) -> some View {
        let generating = viewModel.generatingPeriod == card.periodKey
        return ReportCard(
            systemImage: card.systemImage,
            title: card.title,
            subtitle: card.subtitle,
            trailingTitle: ReportCard.trailingTitle(
                for: generating ? "Generating…" : card.actionTitle,
                isGenerating: generating
            ),
            isGenerating: generating,
            onTap: { viewModel.primaryAction(for: card) }
        )
        .accessibilityIdentifier("reports.card.\(card.periodKey.rawValue)")
    }

    private func yearlyCardView(_ card: YearlyReportCardModel) -> some View {
        let showsPicker = card.availableYears.count > 1
        return ReportCard(
            systemImage: card.systemImage,
            title: card.title,
            subtitle: card.subtitle,
            trailingTitle: ReportCard.trailingTitle(for: card.actionTitle, isGenerating: false),
            trailingBehavior: showsPicker
                ? .interactive { viewModel.primaryAction(for: card) }
                : .decorative,
            onTap: {
                guard !card.availableYears.isEmpty else { return }
                viewModel.primaryAction(for: card)
            }
        )
        .accessibilityIdentifier("reports.card.yearly")
    }

    private func psychologyCard(_ card: PsychologyReportCardModel) -> some View {
        let showsPeriodPicker = card.template.isPeriodic && card.availablePeriods.count > 1
        return ReportCard(
            systemImage: card.systemImage,
            title: card.title,
            subtitle: card.subtitle,
            trailingTitle: ReportCard.trailingTitle(for: card.actionTitle, isGenerating: false),
            trailingBehavior: showsPeriodPicker
                ? .interactive { viewModel.showPsychologyPeriodPicker(for: card) }
                : .decorative,
            onTap: { viewModel.openPsychologyReport(for: card) }
        )
        .accessibilityIdentifier("reports.psychology.\(card.template.rawValue)")
    }

    private func togglePerformanceSection() {
        ExperienceHaptics.play(.selection)
        ExperienceMotion.withAnimation(
            ExperienceMotion.selection,
            reduceMotion: reduceMotion
        ) {
            isPerformanceExpanded.toggle()
        }
    }

    private func togglePsychologySection() {
        ExperienceHaptics.play(.selection)
        ExperienceMotion.withAnimation(
            ExperienceMotion.selection,
            reduceMotion: reduceMotion
        ) {
            isPsychologyExpanded.toggle()
        }
    }
}

struct PsychologyReportPeriodPickerView: View {
    let periods: [PsychologyReportPeriodRef]
    var onSelect: (PsychologyReportPeriodRef) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List(periods, id: \.self) { ref in
                Button {
                    onSelect(ref)
                } label: {
                    if let report = PsychologyReportSessionStore.shared.report(for: ref.reportID) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.dateRangeLabel)
                                .experienceStyle(.headline, color: colors.primaryText)
                            Text("\(report.performance.tradeCount) trades")
                                .experienceStyle(.footnote, color: colors.secondaryText)
                        }
                    } else {
                        Text(ref.periodID)
                    }
                }
            }
            .navigationTitle("Choose Period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

struct TradingReportYearPickerView: View {
    let years: [Int]
    var onSelect: (Int) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List(years, id: \.self) { year in
                Button {
                    onSelect(year)
                } label: {
                    Text(String(year))
                        .experienceStyle(.headline, color: colors.primaryText)
                }
            }
            .navigationTitle("Choose Year")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .accessibilityIdentifier("reports.yearly.picker")
    }
}
