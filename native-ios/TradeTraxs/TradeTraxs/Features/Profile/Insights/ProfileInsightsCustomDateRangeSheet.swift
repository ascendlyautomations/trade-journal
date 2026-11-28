import SwiftUI

struct ProfileInsightsCustomDateRangeSheet: View {
    @Bindable var viewModel: ProfileInsightsViewModel

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
                    Button("Cancel") {
                        viewModel.cancelCustomDateSheet()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applyCustomDateRange()
                        dismiss()
                    }
                    .disabled(!viewModel.canApplyCustomDateRange)
                }
            }
        }
        .accessibilityIdentifier("profile.insights.customDateSheet")
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