import SwiftUI

/// Compact account + filters row for Trade History.
struct TradeHistoryFilterBar: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Binding var browseLayout: ProfileBrowseLayout
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            accountMenu
            Spacer(minLength: 0)
            filtersButton
            ProfileBrowseLayoutToggle(layout: $browseLayout, compact: true)
                .fixedSize()
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
            .experienceFilterCapsule()
            .overlay(alignment: .topTrailing) {
                if viewModel.showsFilterIndicator {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Filters")
        .accessibilityIdentifier("trades.filters")
    }

    private var accountMenu: some View {
        let profileID = viewModel.ownerAccountsProfileID
        let title = viewModel.accountMenuTitle
        return OwnerAccountFilterDropdown(
            accounts: viewModel.accountsForMenu,
            selectedFilter: viewModel.filters.account,
            copyGroups: OwnerAccountFilterMenuSupport.copyGroups(for: profileID),
            isLoadingCopyGroups: OwnerAccountFilterMenuSupport.isLoadingCopyGroups(for: profileID),
            onSelectFilter: { viewModel.setAccountFilter($0) },
            onManageAccounts: { viewModel.openManageAccounts() },
            onManageCopyGroups: { viewModel.openManageCopyTradingGroups() },
            onRequestCopyGroups: {
                OwnerAccountFilterMenuSupport.requestCopyGroupsLoad(profileID: profileID)
            },
            accessibilityIdentifier: "trades.account",
            boundary: .trades,
            profileID: profileID
        ) {
            HStack(spacing: 4) {
                Text(title)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .experienceFilterCapsule()
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountMenuTitle)
    }
}
