import SwiftUI

/// Advanced Trade History filters — applied on confirm (server-side query).
struct TradeHistoryFilterSheet: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Picker("Range", selection: $viewModel.draftFilters.dateRange) {
                        ForEach(TradeHistoryDateRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    if viewModel.draftFilters.dateRange == .custom {
                        DatePicker(
                            "Start",
                            selection: customStartBinding,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "End",
                            selection: customEndBinding,
                            displayedComponents: .date
                        )
                    }
                }

                Section("Result") {
                    Picker("Result", selection: $viewModel.draftFilters.result) {
                        ForEach(TradeHistoryResultFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Result filter")
                }

                Section("P&L") {
                    TextField("Min", text: pnlMinBinding)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel("Minimum P and L")
                    TextField("Max", text: pnlMaxBinding)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel("Maximum P and L")
                }

                Section("Direction") {
                    Picker("Direction", selection: $viewModel.draftFilters.direction) {
                        ForEach(TradeHistoryDirectionFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $viewModel.draftFilters.visibility) {
                        ForEach(TradeHistoryVisibilityFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Public trades are visible on your profile and feed")
                }

                Section("Sort") {
                    Picker("Sort", selection: $viewModel.draftFilters.sort) {
                        ForEach(TradeHistorySort.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.groupedBackground.ignoresSafeArea())
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
            .safeAreaInset(edge: .bottom) {
                ExperienceButton(
                    title: "Apply Filters",
                    kind: .primary,
                    accessibilityIdentifier: "trades.filters.applyBottom"
                ) {
                    viewModel.applyDraftFilters()
                    dismiss()
                }
                .padding(ExperienceSpacing.md)
            }
        }
        .accessibilityIdentifier("trades.filterSheet")
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

    private var pnlMinBinding: Binding<String> {
        Binding(
            get: {
                guard let value = viewModel.draftFilters.pnlMin else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.draftFilters.pnlMin = trimmed.isEmpty
                    ? nil
                    : Decimal(string: trimmed.replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: ",", with: ""))
            }
        )
    }

    private var pnlMaxBinding: Binding<String> {
        Binding(
            get: {
                guard let value = viewModel.draftFilters.pnlMax else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.draftFilters.pnlMax = trimmed.isEmpty
                    ? nil
                    : Decimal(string: trimmed.replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: ",", with: ""))
            }
        )
    }
}
