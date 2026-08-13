import SwiftUI

/// Account + date range menus and Trades entry — compact header controls.
struct DashboardFilterBar: View {
    @Bindable var viewModel: DashboardViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            accountMenu
            dateMenu
            Spacer(minLength: 0)
            Button {
                ExperienceHaptics.play(.selection)
                viewModel.openTradesList()
            } label: {
                ExperienceIcon(icon: .trades, size: .md, color: colors.primaryText)
                    .frame(width: ExperienceAccessibility.minTouchTarget,
                           height: ExperienceAccessibility.minTouchTarget)
                    .background(colors.fillSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trades")
            .accessibilityIdentifier("dashboard.trades")
        }
        .accessibilityIdentifier("dashboard.filters")
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
            menuLabel(selectedAccountTitle)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(selectedAccountTitle)
        .accessibilityIdentifier("dashboard.account")
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
