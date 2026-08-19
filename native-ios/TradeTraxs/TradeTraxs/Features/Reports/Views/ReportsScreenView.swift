import SwiftUI

/// Reports catalog — web Trading Reports periods (This/Last Week & Month).
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
            case .failed(let message) where viewModel.cards.allSatisfy({ $0.availability != .ready }):
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
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.bootstrapIfNeeded()
        }
        .accessibilityIdentifier("reports.home")
    }

    private var catalogScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                intro
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                ForEach(viewModel.cards) { card in
                    ReportTypeCard(
                        model: card,
                        isGenerating: viewModel.generatingPeriod == card.periodKey
                    ) {
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
            Text("Trading Reports")
                .experienceStyle(.title2, color: colors.primaryText)
            Text("Weekly and monthly performance reviews built from your journal — the same reports as web.")
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
        .accessibilityIdentifier("reports.intro")
    }
}
