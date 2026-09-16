import SwiftUI

/// Advanced Trade History filters — applied on confirm.
struct TradeHistoryFilterSheet: View {
    @Bindable var viewModel: TradeHistoryViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var pnlMinText = ""
    @State private var pnlMaxText = ""
    @State private var rrMinText = ""
    @State private var rrMaxText = ""

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
                        TextField("Minimum P&L", text: $pnlMinText.numericInput(.signedPnL))
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Minimum P and L")
                            .onChange(of: pnlMinText) { _, newValue in
                                viewModel.draftFilters.pnlMin = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .signedPnL
                                )
                            }
                    }
                    if pnlPresetBinding.wrappedValue == .maximum {
                        TextField("Maximum P&L", text: $pnlMaxText.numericInput(.signedPnL))
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Maximum P and L")
                            .onChange(of: pnlMaxText) { _, newValue in
                                viewModel.draftFilters.pnlMax = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .signedPnL
                                )
                            }
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
                        TextField("Minimum RR", text: $rrMinText.numericInput(.riskReward))
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Minimum risk reward")
                            .onChange(of: rrMinText) { _, newValue in
                                viewModel.draftFilters.rrMin = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .riskReward
                                )
                            }
                    }
                    if rrPresetBinding.wrappedValue == .maximum {
                        TextField("Maximum RR", text: $rrMaxText.numericInput(.riskReward))
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Maximum risk reward")
                            .onChange(of: rrMaxText) { _, newValue in
                                viewModel.draftFilters.rrMax = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .riskReward
                                )
                            }
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
            .scrollDismissesKeyboard(.interactively)
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
                        syncFilterNumericTextsFromDraft()
                    }
                    .accessibilityIdentifier("trades.filters.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyNumericFiltersFromText()
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
                    applyNumericFiltersFromText()
                    viewModel.applyDraftFilters()
                    dismiss()
                }
                .padding(ExperienceSpacing.md)
            }
        }
        .accessibilityIdentifier("trades.filterSheet")
        .onAppear {
            syncFilterNumericTextsFromDraft()
        }
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
                syncFilterNumericTextsFromDraft()
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
                syncFilterNumericTextsFromDraft()
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

    private func syncFilterNumericTextsFromDraft() {
        pnlMinText = viewModel.draftFilters.pnlMin.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .signedPnL)
        } ?? ""
        pnlMaxText = viewModel.draftFilters.pnlMax.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .signedPnL)
        } ?? ""
        rrMinText = viewModel.draftFilters.rrMin.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .riskReward)
        } ?? ""
        rrMaxText = viewModel.draftFilters.rrMax.map {
            NumericInputFieldSupport.seedEditingText(from: $0, style: .riskReward)
        } ?? ""
    }

    private func applyNumericFiltersFromText() {
        viewModel.draftFilters.pnlMin = NumericInputFieldSupport.parse(pnlMinText, style: .signedPnL)
        viewModel.draftFilters.pnlMax = NumericInputFieldSupport.parse(pnlMaxText, style: .signedPnL)
        viewModel.draftFilters.rrMin = NumericInputFieldSupport.parse(rrMinText, style: .riskReward)
        viewModel.draftFilters.rrMax = NumericInputFieldSupport.parse(rrMaxText, style: .riskReward)
    }
}
