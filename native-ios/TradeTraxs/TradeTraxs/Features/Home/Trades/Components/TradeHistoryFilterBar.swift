import SwiftUI

/// Compact account + filters row for Trade History.
struct TradeHistoryFilterBar: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            accountMenu
            Spacer(minLength: 0)
            filtersButton
        }
        .accessibilityIdentifier("trades.filterBar")
    }

    private var filtersButton: some View {
        Button {
            viewModel.openFilters()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
                Text("Filters")
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .background(colors.fillSecondary, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if viewModel.showsFilterIndicator {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filters")
        .accessibilityIdentifier("trades.filters")
    }

    private var accountMenu: some View {
        OwnerAccountFilterDropdown(
            accounts: viewModel.accountsForMenu,
            isAllAccountsSelected: {
                if case .all = viewModel.filters.account { return true }
                return false
            }(),
            selectedAccountID: {
                if case .account(let id) = viewModel.filters.account { return id }
                return nil
            }(),
            onSelectAll: { viewModel.setAccountFilter(.all) },
            onSelectAccount: { viewModel.setAccountFilter(.account($0)) },
            onManageAccounts: { viewModel.openManageAccounts() },
            accessibilityIdentifier: "trades.account",
            boundary: .trades,
            profileID: viewModel.ownerAccountsProfileID
        ) {
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
    }
}
