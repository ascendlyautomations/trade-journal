import SwiftUI

/// Advanced Trade History filters — applied on confirm.
struct TradeHistoryFilterSheet: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                    Picker("P&L", selection: pnlPresetBinding) {
                        Text("Any").tag(PnLPreset.any)
                        Text("Minimum $").tag(PnLPreset.minimum)
                        Text("Maximum $").tag(PnLPreset.maximum)
                    }
                    .pickerStyle(.segmented)

                    if pnlPresetBinding.wrappedValue == .minimum {
                        TextField("Minimum P&L", text: pnlMinBinding)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Minimum P and L")
                    }
                    if pnlPresetBinding.wrappedValue == .maximum {
                        TextField("Maximum P&L", text: pnlMaxBinding)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Maximum P and L")
                    }
                }

                Section("Risk / Reward") {
                    Picker("Risk / Reward", selection: rrPresetBinding) {
                        Text("Any").tag(RRPreset.any)
                        Text("Minimum R").tag(RRPreset.minimum)
                        Text("Maximum R").tag(RRPreset.maximum)
                    }
                    .pickerStyle(.segmented)

                    if rrPresetBinding.wrappedValue == .minimum {
                        TextField("Minimum RR", text: rrMinBinding)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Minimum risk reward")
                    }
                    if rrPresetBinding.wrappedValue == .maximum {
                        TextField("Maximum RR", text: rrMaxBinding)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Maximum risk reward")
                    }
                }

                Section("Direction") {
                    Picker("Direction", selection: $viewModel.draftFilters.direction) {
                        ForEach(TradeHistoryDirectionFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Account Mode") {
                    Picker("Account Mode", selection: $viewModel.draftFilters.accountMode) {
                        ForEach(TradeHistoryAccountModeFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Trading Session") {
                    Picker("Trading Session", selection: $viewModel.draftFilters.tradingSession) {
                        ForEach(TradeHistorySessionFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }

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

                Section("Visibility") {
                    Picker("Visibility", selection: $viewModel.draftFilters.visibility) {
                        ForEach(TradeHistoryVisibilityFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Public trades are visible on your profile and feed")
                }

                Section("Sort By") {
                    Picker("Sort By", selection: $viewModel.draftFilters.sort) {
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

    private enum PnLPreset: Hashable {
        case any
        case minimum
        case maximum
    }

    private enum RRPreset: Hashable {
        case any
        case minimum
        case maximum
    }

    private var pnlPresetBinding: Binding<PnLPreset> {
        Binding(
            get: {
                if viewModel.draftFilters.pnlMin != nil { return .minimum }
                if viewModel.draftFilters.pnlMax != nil { return .maximum }
                return .any
            },
            set: { preset in
                switch preset {
                case .any:
                    viewModel.draftFilters.pnlMin = nil
                    viewModel.draftFilters.pnlMax = nil
                case .minimum:
                    viewModel.draftFilters.pnlMax = nil
                case .maximum:
                    viewModel.draftFilters.pnlMin = nil
                }
            }
        )
    }

    private var rrPresetBinding: Binding<RRPreset> {
        Binding(
            get: {
                if viewModel.draftFilters.rrMin != nil { return .minimum }
                if viewModel.draftFilters.rrMax != nil { return .maximum }
                return .any
            },
            set: { preset in
                switch preset {
                case .any:
                    viewModel.draftFilters.rrMin = nil
                    viewModel.draftFilters.rrMax = nil
                case .minimum:
                    viewModel.draftFilters.rrMax = nil
                case .maximum:
                    viewModel.draftFilters.rrMin = nil
                }
            }
        )
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
                viewModel.draftFilters.pnlMin = Self.parseDecimal(raw)
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
                viewModel.draftFilters.pnlMax = Self.parseDecimal(raw)
            }
        )
    }

    private var rrMinBinding: Binding<String> {
        Binding(
            get: {
                guard let value = viewModel.draftFilters.rrMin else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { raw in
                viewModel.draftFilters.rrMin = Self.parseDecimal(raw)
            }
        )
    }

    private var rrMaxBinding: Binding<String> {
        Binding(
            get: {
                guard let value = viewModel.draftFilters.rrMax else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { raw in
                viewModel.draftFilters.rrMax = Self.parseDecimal(raw)
            }
        )
    }

    private static func parseDecimal(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(
            string: trimmed
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "R", with: "")
                .replacingOccurrences(of: "r", with: "")
        )
    }
}
