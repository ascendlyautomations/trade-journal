import SwiftUI

/// Focused trade psychology editor, opened from Add Trade Trade Review.
struct AddTradePsychologySheet: View {
    @Bindable var viewModel: AddTradeViewModel
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TradePsychologyFormComponents.convictionSelector(
                        confidenceLevel: $viewModel.confidenceLevel,
                        colors: colors
                    )
                } header: {
                    Text("Conviction")
                } footer: {
                    Text("How strongly you believed in the setup before entry.")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }

                TradePsychologyFormComponents.emotionPickerSection(
                    header: "Before the trade",
                    pickerLabel: "Emotion before trade",
                    selection: $viewModel.emotionPickerSelection,
                    customText: $viewModel.emotionCustomText,
                    accessibilityPrefix: "addTrade.psychology"
                )

                TradePsychologyFormComponents.emotionPickerSection(
                    header: "After the trade",
                    pickerLabel: "Emotion after trade",
                    selection: $viewModel.exitEmotionPickerSelection,
                    customText: $viewModel.exitEmotionCustomText,
                    accessibilityPrefix: "addTrade.psychology.exit"
                )

                TradePsychologyFormComponents.executionRatingSection(
                    rating: $viewModel.executionRatingLevel,
                    accessibilityIdentifier: "addTrade.psychology.executionRating"
                )

                TradePsychologyFormComponents.psychologyNotesSection(
                    text: $viewModel.psychologyNotesText,
                    colors: colors,
                    accessibilityIdentifier: "addTrade.psychology.notes",
                    textInputScreen: "addTradePsychology"
                )
            }
            .listSectionSpacing(TradePsychologyFormComponents.sectionSpacing)
            .scrollDismissesKeyboard(.interactively)
            .experienceTradeTraxsFormStyle(pageBackground: true)
            .experienceNavigationTitle("Trade Psychology")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onClose()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("addTrade.psychology.done")
                }
            }
        }
        .accessibilityIdentifier("addTrade.psychologySheet")
    }
}