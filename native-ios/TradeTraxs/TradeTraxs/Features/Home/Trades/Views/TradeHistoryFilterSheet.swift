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

                    filterSection("Date") {
                        menuPickerRow(title: "Range") {
                            Picker("Range", selection: $viewModel.draftFilters.dateRange) {
                                ForEach(TradeHistoryDateRange.allCases) { range in
                                    Text(range.title).tag(range)
                                }
                            }
                            .labelsHidden()
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
                        }
                    }

                    filterSection("Trading Session") {
                        menuPickerRow(title: "Trading Session") {
                            Picker("Trading Session", selection: $viewModel.draftFilters.tradingSession) {
                                ForEach(TradeHistorySessionFilter.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .labelsHidden()
                        }
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

                    filterSection("P&L") {
                        Picker("P&L", selection: pnlPresetBinding) {
                            Text("Any").tag(PnLPreset.any)
                            Text("Minimum $").tag(PnLPreset.minimum)
                            Text("Maximum $").tag(PnLPreset.maximum)
                        }
                        .pickerStyle(.segmented)

                        if pnlPresetBinding.wrappedValue == .minimum {
                            compactNumericField(
                                placeholder: "Minimum P&L",
                                text: $pnlMinText,
                                style: .signedPnL,
                                accessibilityLabel: "Minimum P and L"
                            ) { newValue in
                                viewModel.draftFilters.pnlMin = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .signedPnL
                                )
                            }
                        }
                        if pnlPresetBinding.wrappedValue == .maximum {
                            compactNumericField(
                                placeholder: "Maximum P&L",
                                text: $pnlMaxText,
                                style: .signedPnL,
                                accessibilityLabel: "Maximum P and L"
                            ) { newValue in
                                viewModel.draftFilters.pnlMax = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .signedPnL
                                )
                            }
                        }
                    }

                    filterSection("Risk / Reward") {
                        Picker("Risk / Reward", selection: rrPresetBinding) {
                            Text("Any").tag(RRPreset.any)
                            Text("Minimum R").tag(RRPreset.minimum)
                            Text("Maximum R").tag(RRPreset.maximum)
                        }
                        .pickerStyle(.segmented)

                        if rrPresetBinding.wrappedValue == .minimum {
                            compactNumericField(
                                placeholder: "Minimum RR",
                                text: $rrMinText,
                                style: .riskReward,
                                accessibilityLabel: "Minimum risk reward"
                            ) { newValue in
                                viewModel.draftFilters.rrMin = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .riskReward
                                )
                            }
                        }
                        if rrPresetBinding.wrappedValue == .maximum {
                            compactNumericField(
                                placeholder: "Maximum RR",
                                text: $rrMaxText,
                                style: .riskReward,
                                accessibilityLabel: "Maximum risk reward"
                            ) { newValue in
                                viewModel.draftFilters.rrMax = NumericInputFieldSupport.parse(
                                    newValue,
                                    style: .riskReward
                                )
                            }
                        }
                    }

                    filterSection("Direction") {
                        Picker("Direction", selection: $viewModel.draftFilters.direction) {
                            ForEach(TradeHistoryDirectionFilter.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    filterSection("Account Mode") {
                        Picker("Account Mode", selection: $viewModel.draftFilters.accountMode) {
                            ForEach(TradeHistoryAccountModeFilter.allCases) { value in
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
        }
        .accessibilityIdentifier("trades.filterSheet")
        .onAppear {
            syncFilterNumericTextsFromDraft()
        }
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

    private func compactNumericField(
        placeholder: String,
        text: Binding<String>,
        style: NumericInputStyle,
        accessibilityLabel: String,
        onChange: @escaping (String) -> Void
    ) -> some View {
        TextField(placeholder, text: text.numericInput(style))
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.plain)
            .font(ExperienceTypography.body)
            .foregroundStyle(colors.primaryText)
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.xs)
            .background(colors.fillSecondary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
            .onChange(of: text.wrappedValue) { _, newValue in
                onChange(newValue)
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
