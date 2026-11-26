import SwiftUI

enum TradingReportCustomRangeSheetTarget {
    case performance
    case psychology
}

struct TradingReportCustomRangeSheet: View {
    @Bindable var viewModel: ReportsScreenViewModel
    var target: TradingReportCustomRangeSheetTarget = .performance

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private let monthSymbols: [String] = {
        Calendar.current.monthSymbols
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Month", selection: $viewModel.draftCustomMonth) {
                        ForEach(1 ... 12, id: \.self) { month in
                            Text(monthSymbols[month - 1]).tag(month)
                        }
                    }
                    .tint(colors.accent)
                    Picker("Year", selection: $viewModel.draftCustomYear) {
                        ForEach(selectableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .tint(colors.accent)
                } header: {
                    Text("Quick select")
                        .foregroundStyle(colors.secondaryText)
                } footer: {
                    Text("Jump to a full calendar month, or fine-tune the exact dates below.")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                .onChange(of: viewModel.draftCustomMonth) { _, _ in
                    viewModel.applyQuickMonthSelection()
                }
                .onChange(of: viewModel.draftCustomYear) { _, _ in
                    viewModel.applyQuickMonthSelection()
                }

                Section {
                    ExperienceFormDateRangeFields(
                        start: customStartBinding,
                        end: customEndBinding,
                        maximumDate: Date()
                    )
                } header: {
                    Text("Date range")
                        .foregroundStyle(colors.secondaryText)
                }

                if let message = viewModel.customRangeValidationMessage {
                    Section {
                        Text(message)
                            .experienceStyle(.footnote, color: colors.error)
                    }
                }

                Section {
                    ExperienceButton(
                        title: "Generate Report",
                        kind: .primary,
                        isEnabled: viewModel.canGenerateCustomReport
                    ) {
                        switch target {
                        case .performance:
                            viewModel.generateCustomReport()
                        case .psychology:
                            viewModel.generateCustomPsychologyReport()
                        }
                        dismiss()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .listSectionSeparatorTint(colors.separator)
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .tint(colors.accent)
            .experienceNavigationTitle("Custom Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
            }
        }
        .accessibilityIdentifier("reports.customRange.sheet")
    }

    private var selectableYears: [Int] {
        TradingReportCustomRangeSupport.selectableYears(tradeYears: viewModel.availableYears)
    }

    private var customStartBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftCustomRangeStart ?? Date() },
            set: { viewModel.draftCustomRangeStart = $0 }
        )
    }

    private var customEndBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftCustomRangeEnd ?? Date() },
            set: { viewModel.draftCustomRangeEnd = $0 }
        )
    }
}