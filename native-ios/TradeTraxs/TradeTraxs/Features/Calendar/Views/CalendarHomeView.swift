import SwiftUI

struct CalendarHomeView: View {
    @State private var viewModel: CalendarViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: CalendarViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub,
                rpc: data.rpc
            )
        )
    }

    /// Tests / previews.
    init(viewModel: CalendarViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.month == nil {
                    ExperienceListSkeleton(style: .calendarGrid)
                } else {
                    content
                }
            case .failed(let message):
                if viewModel.month == nil {
                    ExperienceErrorState(
                        title: "Couldn't load calendar",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                } else {
                    content
                }
            case .loaded:
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Calendar")
        .toolbar { toolbar }
        .refreshable { await viewModel.refresh() }
        .onAppear { viewModel.loadIfNeeded() }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            viewModel.handleAccountMutation()
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("calendar.home")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                header
                if let month = viewModel.month {
                    CalendarMonthGrid(month: month, selectedDayKey: nil) { dayKey in
                        viewModel.selectDay(dayKey)
                    }
                    .opacity(viewModel.isMonthTransitioning && !reduceMotion ? 0.55 : 1)
                    .animation(
                        ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
                        value: viewModel.isMonthTransitioning
                    )
                    .animation(
                        ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
                        value: month.title
                    )

                    CalendarMonthSummaryBar(summary: month.monthSummary)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.lg)
        }
    }

    private var header: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(colors.fillSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .experienceTouchTarget()
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.month?.title ?? "—")
                    .experienceStyle(.headline, color: colors.primaryText)
                Button("Today") {
                    viewModel.goToCurrentMonth()
                }
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(colors.accent)
            }

            Spacer()

            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(colors.fillSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .experienceTouchTarget()
            .accessibilityLabel("Next month")
        }
        .padding(.bottom, ExperienceSpacing.xxs)
        .accessibilityIdentifier("calendar.header")
    }

    private var accountMenu: some View {
        OwnerAccountFilterDropdown(
            accounts: viewModel.accountsForMenu,
            isAllAccountsSelected: {
                if case .all = viewModel.accountFilter { return true }
                return false
            }(),
            selectedAccountID: {
                if case .account(let id) = viewModel.accountFilter { return id }
                return nil
            }(),
            onSelectAll: { viewModel.setAccountFilter(.all) },
            onSelectAccount: { viewModel.setAccountFilter(.account($0)) },
            onManageAccounts: { viewModel.openManageAccounts() },
            accessibilityIdentifier: "calendar.account",
            boundary: .calendar,
            profileID: viewModel.ownerAccountsProfileID
        ) {
            HStack(spacing: 4) {
                Text(viewModel.accountFilterToolbarTitle)
                    .experienceStyle(.footnote, color: colors.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.accent)
            }
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountFilterTitle)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: ExperienceSpacing.sm) {
                if viewModel.isMonthTransitioning {
                    ProgressView()
                }
                accountMenu
            }
        }
    }
}
