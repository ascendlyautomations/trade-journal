import SwiftUI

/// Account + date range menus with Trades, Reports, and Withdrawals tools — compact header controls.
struct DashboardFilterBar: View {
    @Bindable var viewModel: DashboardViewModel

    @Environment(\.themeColors) private var colors
    @State private var filterBarWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            accountMenu
                .layoutPriority(1)
            dateMenu
                .layoutPriority(2)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: ExperienceSpacing.xxs)
            dashboardToolButtons
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { filterBarWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in
                        filterBarWidth = width
                    }
            }
        }
        .accessibilityIdentifier("dashboard.filters")
    }

    private var dashboardToolButtons: some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            toolButton(
                icon: .trades,
                accessibilityLabel: "Trades",
                accessibilityIdentifier: "dashboard.trades"
            ) {
                ExperienceHaptics.play(.selection)
                viewModel.openTradesList()
            }
            toolButton(
                icon: .reports,
                accessibilityLabel: "Reports",
                accessibilityIdentifier: "dashboard.reports"
            ) {
                viewModel.openReports()
            }
            toolButton(
                icon: .payouts,
                accessibilityLabel: "Withdrawals",
                accessibilityIdentifier: "dashboard.withdrawals"
            ) {
                viewModel.openWithdrawalsHistory()
            }
        }
    }

    private func toolButton(
        icon: AppIcon,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ExperienceIcon(icon: icon, size: .md, color: colors.primaryText)
                .frame(
                    width: ExperienceAccessibility.minTouchTarget,
                    height: ExperienceAccessibility.minTouchTarget
                )
                .background(colors.fillSecondary, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
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
            accessibilityIdentifier: "dashboard.account",
            boundary: .dashboard,
            profileID: viewModel.ownerAccountsProfileID
        ) {
            accountMenuLabel(selectedAccountTitle)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(selectedAccountTitle)
    }

    private var selectedAccountTitle: String {
        switch viewModel.accountFilter {
        case .all:
            return "All Accounts"
        case .account(let id):
            if let account = viewModel.accounts.first(where: { $0.id == id }) {
                return viewModel.accountMenuTitle(for: account)
            }
            return viewModel.accountFilterTitle
        }
    }

    private var dateMenu: some View {
        Menu {
            ForEach(DashboardDateRange.allCases) { range in
                Button {
                    viewModel.setDateRange(range)
                } label: {
                    if viewModel.dateRange == range {
                        Label(range.title, systemImage: "checkmark")
                    } else {
                        Text(range.title)
                    }
                }
            }
        } label: {
            menuLabel(viewModel.dateRange.title)
        }
        .accessibilityLabel("Date range")
        .accessibilityValue(viewModel.dateRange.title)
        .accessibilityIdentifier("dashboard.dateRange")
    }

    private func accountMenuLabel(_ title: String) -> some View {
        menuLabel(title)
            .fixedSize(horizontal: true, vertical: false)
            .frame(
                maxWidth: maxAccountSelectorWidth(in: filterBarWidth),
                alignment: .leading
            )
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .experienceStyle(.footnote, color: colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .frame(minHeight: 32)
        .background(colors.fillSecondary)
        .clipShape(Capsule())
    }

    /// Caps account label width so three tool buttons + date range stay on one row (176 max unchanged).
    private func maxAccountSelectorWidth(in totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return 176 }
        let touch = ExperienceAccessibility.minTouchTarget
        let rowGap = ExperienceSpacing.xs
        let toolGap = ExperienceSpacing.xxs
        let dateReserve: CGFloat = 76
        let toolsWidth = touch * 3 + toolGap * 2
        let reserved = dateReserve + toolsWidth + rowGap * 2 + ExperienceSpacing.xxs
        let available = totalWidth - reserved
        return min(max(available, 112), 176)
    }
}
