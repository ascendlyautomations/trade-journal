import SwiftUI

/// Account + date range menus with Trades and Reports tools — compact header controls.
struct DashboardFilterBar: View {
    @Bindable var viewModel: DashboardViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            accountMenu
            dateMenu
            Spacer(minLength: 0)
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
            toolProfileBankButton(
                accessibilityLabel: "Payouts",
                accessibilityIdentifier: "dashboard.payouts"
            ) {
                ExperienceHaptics.play(.selection)
                viewModel.openPayouts()
            }
        }
        .accessibilityIdentifier("dashboard.filters")
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

    private func toolProfileBankButton(
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ProfileBankIcon.image(color: colors.primaryText)
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
            menuLabel(selectedAccountTitle)
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

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .experienceStyle(.footnote, color: colors.primaryText)
                .lineLimit(1)
            ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .frame(minHeight: 32)
        .background(colors.fillSecondary)
        .clipShape(Capsule())
    }
}
