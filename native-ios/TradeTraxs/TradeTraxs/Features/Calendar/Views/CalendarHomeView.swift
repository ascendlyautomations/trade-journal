import SwiftUI

struct CalendarHomeView: View {
    @State private var viewModel: CalendarViewModel

    @Environment(\.themeColors) private var colors

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: CalendarViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub
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
                    ProgressView("Loading calendar…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(colors.groupedBackground.ignoresSafeArea())
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
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                header
                if let month = viewModel.month {
                    CalendarMonthGrid(month: month, selectedDayKey: nil) { dayKey in
                        viewModel.selectDay(dayKey)
                    }
                    .opacity(viewModel.isMonthTransitioning ? 0.7 : 1)

                    CalendarMonthSummaryBar(summary: month.monthSummary)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.xl)
        }
    }

    private var header: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(colors.fillSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.month?.title ?? "—")
                    .experienceStyle(.headline, color: colors.primaryText)
                Button("Today") {
                    viewModel.goToCurrentMonth()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
            }

            Spacer()

            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(colors.fillSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
        .accessibilityIdentifier("calendar.header")
    }

    private var accountMenu: some View {
        Menu {
            Button {
                viewModel.setAccountFilter(.all)
            } label: {
                if case .all = viewModel.accountFilter {
                    Label("All Accounts", systemImage: "checkmark")
                } else {
                    Text("All Accounts")
                }
            }
            ForEach(viewModel.accounts) { account in
                Button {
                    viewModel.setAccountFilter(.account(account.id))
                } label: {
                    let title = viewModel.accountMenuTitle(for: account)
                    if case .account(let id) = viewModel.accountFilter, id == account.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
            Divider()
            Button {
                viewModel.openManageAccounts()
            } label: {
                Label("Manage Accounts", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.accountFilterToolbarTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(colors.accent)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountFilterTitle)
        .accessibilityIdentifier("calendar.account")
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
