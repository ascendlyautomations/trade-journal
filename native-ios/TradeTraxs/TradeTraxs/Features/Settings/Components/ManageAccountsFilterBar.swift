import SwiftUI

/// Compact prop-firm + account-type filters for Manage Accounts.
struct ManageAccountsFilterBar: View {
    @Bindable var viewModel: ManageAccountsViewModel
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            filterMenu(
                title: viewModel.propFirmFilter.menuTitle,
                accessibilityID: "manageAccounts.filter.propFirm"
            ) {
                Button {
                    viewModel.setPropFirmFilter(.all)
                } label: {
                    filterRow("All Prop Firms", selected: viewModel.propFirmFilter == .all)
                }
                if !viewModel.availablePropFirms.isEmpty {
                    Divider()
                    ForEach(viewModel.availablePropFirms, id: \.self) { firm in
                        Button {
                            viewModel.setPropFirmFilter(.firm(firm))
                        } label: {
                            filterRow(firm, selected: viewModel.propFirmFilter == .firm(firm))
                        }
                    }
                }
            }

            filterMenu(
                title: viewModel.modeFilter.menuTitle,
                accessibilityID: "manageAccounts.filter.mode"
            ) {
                Button {
                    viewModel.setModeFilter(.all)
                } label: {
                    filterRow("All Types", selected: viewModel.modeFilter == .all)
                }
                if !viewModel.availableModes.isEmpty {
                    Divider()
                    ForEach(viewModel.availableModes, id: \.self) { mode in
                        Button {
                            viewModel.setModeFilter(.mode(mode))
                        } label: {
                            filterRow(
                                ManageAccountsFiltering.modeFilterLabel(mode),
                                selected: viewModel.modeFilter == .mode(mode)
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            filterMenu(
                title: "Sort: \(viewModel.sort.menuTitle)",
                accessibilityID: "manageAccounts.filter.sort"
            ) {
                ForEach(
                    [
                        ManageAccountsFiltering.Sort.accountName,
                        .propFirm,
                        .accountType,
                    ],
                    id: \.self
                ) { option in
                    Button {
                        viewModel.setSort(option)
                    } label: {
                        filterRow(option.menuTitle, selected: viewModel.sort == option)
                    }
                }
            }
        }
        .accessibilityIdentifier("manageAccounts.filterBar")
    }

    @ViewBuilder
    private func filterMenu<Content: View>(
        title: String,
        accessibilityID: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .background(colors.fillSecondary, in: Capsule())
        }
        .accessibilityIdentifier(accessibilityID)
    }

    private func filterRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}
