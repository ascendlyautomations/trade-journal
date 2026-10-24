import SwiftUI

/// Dashboard scope filters — time period, account type, visibility (account picker stays in the header).
struct DashboardScopeFilterSheet: View {
    @Bindable var viewModel: DashboardViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private let sectionSpacing = ExperienceSpacing.lg
    private let labelControlSpacing = ExperienceSpacing.xs

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    filterSection("Time Period") {
                        menuPickerRow(title: "Period") {
                            Picker("Time Period", selection: $viewModel.draftScopeFilters.timePeriod) {
                                ForEach(DashboardTimePeriodPicker.allCases) { period in
                                    Text(period.title).tag(period)
                                }
                            }
                            .labelsHidden()
                        }

                        if viewModel.draftScopeFilters.timePeriod == .custom {
                            VStack(spacing: labelControlSpacing) {
                                DatePicker(
                                    "Start",
                                    selection: customStartBinding,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                DatePicker(
                                    "End",
                                    selection: customEndBinding,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                            }
                        }
                    }

                    filterSection("Account Type") {
                        Picker("Account Type", selection: $viewModel.draftScopeFilters.accountType) {
                            ForEach(DashboardScopeFilterSupport.dashboardAccountTypeCases) { mode in
                                Text(DashboardScopeFilterSupport.accountTypeTitle(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Account type filter")
                    }

                    filterSection("Visibility") {
                        Picker("Visibility", selection: $viewModel.draftScopeFilters.visibility) {
                            ForEach(DashboardTradeVisibilityFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHint("Public trades appear on your profile and feed")
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .experienceNavigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("dashboard.filters.cancel")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        viewModel.resetDraftScopeFilters()
                    }
                    .accessibilityIdentifier("dashboard.filters.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applyDraftScopeFilters()
                        dismiss()
                    }
                    .accessibilityIdentifier("dashboard.filters.apply")
                }
            }
        }
        .accessibilityIdentifier("dashboard.filterSheet")
    }

    @ViewBuilder
    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: labelControlSpacing) {
            Text(title.uppercased())
                .font(ExperienceTypography.caption.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
            content()
        }
    }

    @ViewBuilder
    private func menuPickerRow<PickerContent: View>(
        title: String,
        @ViewBuilder picker: () -> PickerContent
    ) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.body, color: colors.primaryText)
            Spacer(minLength: ExperienceSpacing.xs)
            picker()
                .pickerStyle(.menu)
                .tint(colors.accent)
        }
        .frame(minHeight: ExperienceSpacing.minTouchTarget, alignment: .center)
        .padding(.horizontal, ExperienceSpacing.sm)
        .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var customStartBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftScopeFilters.customStart ?? Date() },
            set: { viewModel.draftScopeFilters.customStart = $0 }
        )
    }

    private var customEndBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftScopeFilters.customEnd ?? Date() },
            set: { viewModel.draftScopeFilters.customEnd = $0 }
        )
    }
}
