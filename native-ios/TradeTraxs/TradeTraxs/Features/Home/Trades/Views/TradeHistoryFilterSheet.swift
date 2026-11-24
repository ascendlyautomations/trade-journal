import SwiftUI

/// Advanced Trade History filters, applied on confirm.
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
                    inlineFilterField(title: "Sort By") {
                        sortDropdownMenu
                    }

                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        inlineFilterField(title: "Date") {
                            dateDropdownMenu
                        }
                        inlineFilterField(title: "Session") {
                            sessionDropdownMenu
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

                    picturesOnlyToggle
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
    private func inlineFilterField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: labelControlSpacing) {
            Text(title.uppercased())
                .font(ExperienceTypography.caption.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sortDropdownMenu: some View {
        TradeHistoryFilterDropdownMenu(
            selectionTitle: viewModel.draftFilters.sort.title,
            accessibilityLabel: "Sort by"
        ) {
            ForEach(TradeHistorySort.allCases) { value in
                Button {
                    viewModel.draftFilters.sort = value
                } label: {
                    if viewModel.draftFilters.sort == value {
                        Label(value.title, systemImage: "checkmark")
                    } else {
                        Text(value.title)
                    }
                }
            }
        }
        .accessibilityIdentifier("trades.filters.sort")
    }

    private var dateDropdownMenu: some View {
        TradeHistoryFilterDropdownMenu(
            selectionTitle: viewModel.draftFilters.dateRange.title,
            accessibilityLabel: "Date"
        ) {
            ForEach(TradeHistoryDateRange.allCases) { range in
                Button {
                    viewModel.draftFilters.dateRange = range
                } label: {
                    if viewModel.draftFilters.dateRange == range {
                        Label(range.title, systemImage: "checkmark")
                    } else {
                        Text(range.title)
                    }
                }
            }
        }
        .accessibilityIdentifier("trades.filters.date")
    }

    private var sessionDropdownMenu: some View {
        TradeHistoryFilterDropdownMenu(
            selectionTitle: viewModel.draftFilters.tradingSession.title,
            accessibilityLabel: "Session"
        ) {
            ForEach(TradeHistorySessionFilter.allCases) { value in
                Button {
                    viewModel.draftFilters.tradingSession = value
                } label: {
                    if viewModel.draftFilters.tradingSession == value {
                        Label(value.title, systemImage: "checkmark")
                    } else {
                        Text(value.title)
                    }
                }
            }
        }
        .accessibilityIdentifier("trades.filters.session")
    }

    private var picturesOnlyToggle: some View {
        Toggle(isOn: $viewModel.draftFilters.pictureOnly) {
            Text("Trades With Pictures")
                .experienceStyle(.callout, color: colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(SwitchToggleStyle(tint: colors.accent))
        .tradeHistoryFilterControlChrome(surface: .toggleRow)
        .accessibilityIdentifier("trades.filters.tradesWithPictures")
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
