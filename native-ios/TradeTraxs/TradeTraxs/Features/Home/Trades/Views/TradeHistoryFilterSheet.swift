import SwiftUI

/// Advanced Trade History filters — applied on confirm.
struct TradeHistoryFilterSheet: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private let sectionSpacing = ExperienceSpacing.lg
    private let labelControlSpacing = ExperienceSpacing.xs

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    filterSection("Sort By") {
                        menuPickerRow(title: "Sort By") {
                            Picker("Sort By", selection: $viewModel.draftFilters.sort) {
                                ForEach(TradeHistorySort.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        inlineFilterMenu(title: "Date") {
                            Picker("Range", selection: $viewModel.draftFilters.dateRange) {
                                ForEach(TradeHistoryDateRange.allCases) { range in
                                    Text(range.title).tag(range)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        inlineFilterMenu(title: "Session") {
                            Picker("Trading Session", selection: $viewModel.draftFilters.tradingSession) {
                                ForEach(TradeHistorySessionFilter.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    if viewModel.draftFilters.dateRange == .custom {
                        VStack(spacing: labelControlSpacing) {
                            DatePicker(
                                "Start",
                                selection: customStartBinding,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            DatePicker(
                                "End",
                                selection: customEndBinding,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                    }

                    filterSection("Account Mode") {
                        Picker("Account Mode", selection: $viewModel.draftFilters.accountMode) {
                            ForEach(TradeHistoryAccountModeFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    filterSection("Result") {
                        Picker("Result", selection: $viewModel.draftFilters.result) {
                            ForEach(TradeHistoryResultFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Result filter")
                    }

                    filterSection("Direction") {
                        Picker("Direction", selection: $viewModel.draftFilters.direction) {
                            ForEach(TradeHistoryDirectionFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    filterSection("Visibility") {
                        Picker("Visibility", selection: $viewModel.draftFilters.visibility) {
                            ForEach(TradeHistoryVisibilityFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHint("Public trades are visible on your profile and feed")
                    }

                    Toggle(isOn: $viewModel.draftFilters.pictureOnly) {
                        Text("Picture Only")
                            .experienceStyle(.callout, color: colors.primaryText)
                    }
                    .accessibilityIdentifier("trades.filters.pictureOnly")
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .experienceNavigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("trades.filters.cancel")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        viewModel.resetDraftFilters()
                    }
                    .accessibilityIdentifier("trades.filters.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applyDraftFilters()
                        dismiss()
                    }
                    .accessibilityIdentifier("trades.filters.apply")
                }
            }
        }
        .accessibilityIdentifier("trades.filterSheet")
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
    private func inlineFilterMenu<PickerContent: View>(
        title: String,
        @ViewBuilder picker: () -> PickerContent
    ) -> some View {
        VStack(alignment: .leading, spacing: labelControlSpacing) {
            Text(title.uppercased())
                .font(ExperienceTypography.caption.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
            HStack(spacing: ExperienceSpacing.sm) {
                picker()
                    .pickerStyle(.menu)
                    .tint(colors.accent)
            }
            .frame(maxWidth: .infinity, minHeight: ExperienceSpacing.minTouchTarget, alignment: .center)
            .padding(.horizontal, ExperienceSpacing.sm)
            .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            get: { viewModel.draftFilters.customStart ?? Date() },
            set: { viewModel.draftFilters.customStart = $0 }
        )
    }

    private var customEndBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftFilters.customEnd ?? Date() },
            set: { viewModel.draftFilters.customEnd = $0 }
        )
    }
}
