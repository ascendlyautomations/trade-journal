import SwiftUI

struct BacktestLabCustomTimeRangeSheet: View {
    @Bindable var viewModel: BacktestLabViewModel
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start",
                        selection: customStartBinding,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End",
                        selection: customEndBinding,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .experienceNavigationTitle("Custom Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applyCustomTimeRange()
                        dismiss()
                    }
                    .disabled(!viewModel.canApplyCustomTimeRange)
                }
            }
        }
        .accessibilityIdentifier("backtest.lab.customTimeSheet")
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