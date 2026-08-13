import SwiftUI

/// Compact account menu + Filters entry for Trade History.
struct TradeHistoryFilterBar: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            accountMenu
            Spacer(minLength: 0)
            Button {
                viewModel.openFilters()
            } label: {
                HStack(spacing: 4) {
                    ExperienceIcon(icon: .filter, size: .sm, color: colors.primaryText)
                    Text("Filters")
                        .experienceStyle(.footnote, color: colors.primaryText)
                    if viewModel.filters.hasActiveConstraints {
                        Circle()
                            .fill(colors.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, ExperienceSpacing.sm)
                .frame(minHeight: 32)
                .background(colors.fillSecondary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters")
            .accessibilityIdentifier("trades.filters")
        }
        .accessibilityIdentifier("trades.filterBar")
    }

    private var accountMenu: some View {
        Menu {
            Button {
                viewModel.setAccountFilter(.all)
            } label: {
                if case .all = viewModel.filters.account {
                    Label("All Accounts", systemImage: "checkmark")
                } else {
                    Text("All Accounts")
                }
            }
            ForEach(viewModel.accounts) { account in
                Button {
                    viewModel.setAccountFilter(.account(account.id))
                } label: {
                    if case .account(let id) = viewModel.filters.account, id == account.id {
                        Label(account.name, systemImage: "checkmark")
                    } else {
                        Text(account.name)
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
                Text(viewModel.accountMenuTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .background(colors.fillSecondary, in: Capsule())
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountMenuTitle)
        .accessibilityIdentifier("trades.account")
    }
}
