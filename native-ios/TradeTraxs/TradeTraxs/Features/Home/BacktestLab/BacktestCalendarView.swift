import SwiftUI

/// Backtest-only calendar (Dashboard month grid parity, account + strategy filters).
struct BacktestCalendarView: View {
    @State private var viewModel: BacktestCalendarViewModel
    @State private var entitlementGateRevision = 0

    private let data: DataEnvironment
    private let embeddedInTraxsProPreview: Bool

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        embeddedInTraxsProPreview: Bool = false
    ) {
        self.embeddedInTraxsProPreview = embeddedInTraxsProPreview
        _viewModel = State(
            initialValue: BacktestCalendarViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                loadsTraxsProPreviewSampleOnly: embeddedInTraxsProPreview
            )
        )
        self.data = data
    }

    var body: some View {
        Group {
            if showsEntitlementVerification {
                TraxProEntitlementVerificationView(profileID: viewerProfileID) {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            } else if restrictsBacktestLab {
                gatedContent
            } else {
                calendarBody
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Backtest Calendar")
        .toolbar { toolbar }
        .refreshable {
            guard !restrictsBacktestLab else { return }
            await viewModel.refresh()
        }
        .task(id: restrictsBacktestLab) {
            guard !restrictsBacktestLab, !showsEntitlementVerification else { return }
            viewModel.loadIfNeeded()
        }
        .task(id: showsEntitlementVerification) {
            if showsEntitlementVerification {
                await TraxProEntitlementRefreshAction.refresh(data: data)
            }
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            guard !restrictsBacktestLab else { return }
            Task { await viewModel.refresh() }
        }
        .onOwnerAccountMutation {
            guard !restrictsBacktestLab else { return }
            viewModel.handleAccountMutation()
        }
        .onCopyTradingGroupsMutation {
            guard !restrictsBacktestLab else { return }
            viewModel.handleCopyTradingGroupsMutation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .accessibilityIdentifier("backtest.calendar.root")
    }

    private var showsEntitlementVerification: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewerProfileID
        )
    }

    private var restrictsBacktestLab: Bool {
        if embeddedInTraxsProPreview { return false }
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictBacktestLab(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewerProfileID
        )
    }

    private var viewerProfileID: ProfileID? {
        guard let bootstrap = SessionBootstrapStore.shared.last else { return nil }
        return ProfileID(bootstrap.data.viewer.id)
    }

    private var gatedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                TraxProFeaturePreviewCard(
                    title: "TraxsPro Backtest Calendar",
                    message: "Open your backtest P&L calendar with TraxsPro.",
                    feature: .backtestLab,
                    previewEntryPoint: .backtestLabGate,
                    accessibilityIdentifier: "backtest.calendar.gate"
                )
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.xs)
        }
    }

    @ViewBuilder
    private var calendarBody: some View {
        switch viewModel.phase {
        case .idle:
            ExperienceListSkeleton(style: .calendarGrid)
        case .loading where viewModel.allTrades.isEmpty:
            ExperienceListSkeleton(style: .calendarGrid)
        case .failed(let message) where viewModel.allTrades.isEmpty:
            ExperienceErrorState(
                title: "Couldn't load calendar",
                message: message,
                onRetry: { Task { await viewModel.refresh() } }
            )
        default:
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                filterBar
                monthHeader
                CalendarMonthGrid(month: viewModel.month, selectedDayKey: nil) { dayKey in
                    viewModel.selectDay(dayKey)
                }
                CalendarMonthSummaryBar(summary: viewModel.month.monthSummary)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.lg)
        }
    }

    private var filterBar: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            accountFilterMenu
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            strategyFilterMenu
        }
        .padding(.bottom, ExperienceSpacing.xxs)
        .accessibilityIdentifier("backtest.calendar.filters")
    }

    private var accountFilterMenu: some View {
        let profileID = viewModel.ownerAccountsProfileID
        return OwnerAccountFilterDropdown(
            accounts: viewModel.backtestAccountsForMenu,
            selectedFilter: viewModel.accountFilter,
            copyGroups: [],
            isLoadingCopyGroups: false,
            onSelectFilter: { viewModel.setAccountFilter($0) },
            onManageAccounts: { viewModel.openManageAccounts() },
            onManageCopyGroups: {},
            onRequestCopyGroups: {},
            accessibilityIdentifier: "backtest.calendar.account",
            includesCopyTradingMenu: false,
            boundary: .trades,
            profileID: profileID
        ) {
            filterCapsuleLabel(viewModel.accountMenuTitle)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountMenuTitle)
    }

    private var strategyFilterMenu: some View {
        Menu {
            ForEach(viewModel.strategyOptions, id: \.self) { option in
                Button {
                    viewModel.setStrategy(option)
                } label: {
                    if option == BacktestLabMetrics.allStrategiesToken {
                        Text("All Strategies")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            filterCapsuleLabel(viewModel.strategyMenuTitle)
        }
        .accessibilityIdentifier("backtest.calendar.strategy")
    }

    private func filterCapsuleLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .experienceStyle(.footnote, color: colors.primaryText)
                .lineLimit(1)
            ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .frame(minHeight: 32)
        .tradingRulesFilterChip()
        .experienceControlHitTarget()
    }

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 36, height: 36)
                    .experienceFilterIconCircle()
                    .experienceTouchTarget()
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.month.title)
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
                    .experienceFilterIconCircle()
                    .experienceTouchTarget()
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Next month")
        }
        .padding(.bottom, ExperienceSpacing.xxs)
        .accessibilityIdentifier("backtest.calendar.header")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if viewModel.phase == .loading, !viewModel.allTrades.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                ExperienceIndeterminateProgress()
            }
        }
    }
}