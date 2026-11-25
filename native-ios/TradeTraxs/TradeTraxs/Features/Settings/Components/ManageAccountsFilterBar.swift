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
                    filterRow("All Accounts", selected: viewModel.propFirmFilter == .all)
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
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .minimumScaleFactor(0.85)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .experienceFilterCapsule()
            .experienceControlHitTarget()
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
