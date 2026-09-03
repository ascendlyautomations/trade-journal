import SwiftUI

/// Reports catalog — Performance Reports + Psychology Reports.
struct ReportsScreenView: View {
    @State private var viewModel: ReportsScreenViewModel

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
        .accessibilityIdentifier("reports.home")
    }

    private var catalogScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                intro
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                sectionHeader("Performance Reports")
                ForEach(viewModel.cards) { card in
                    ReportTypeCard(
                        model: card,
                        isGenerating: viewModel.generatingPeriod == card.periodKey
                    ) {
                        viewModel.primaryAction(for: card)
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                }

                sectionHeader("Psychology Reports")
                ForEach(viewModel.psychologyCards) { card in
                    PsychologyReportTypeCard(model: card) {
                        viewModel.primaryAction(for: card)
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                }
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.modalPresent, reduceMotion: reduceMotion),
                value: viewModel.cards.map(\.actionTitle)
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Your Reports")
                .experienceStyle(.title2, color: colors.primaryText)
            Text("Performance reviews and psychology insights from your journal.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.16),
                            colors.fillSecondary.opacity(0.65),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.headline, color: colors.primaryText)
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PsychologyReportTypeCard: View {
    let model: PsychologyReportCardModel
    var onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ExperienceSpacing.md) {
                Image(systemName: model.systemImage)
                    .font(.title2)
                    .foregroundStyle(colors.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text(model.subtitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(model.actionTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
            .padding(ExperienceSpacing.md)
            .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
