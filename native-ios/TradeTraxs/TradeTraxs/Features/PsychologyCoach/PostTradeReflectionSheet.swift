import SwiftUI

/// Optional lightweight reflection after saving a trade.
struct PostTradeReflectionSheet: View {
    let trade: Trade
    let onSave: (String?, Int?) async -> Void
    let onSkip: () -> Void

    @State private var exitEmotion = ""
    @State private var executionRating = 0
    @State private var reflectionText = ""
    @State private var isSaving = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Form {
                Section("Emotion After Trade") {
                    Picker("Emotion", selection: $exitEmotion) {
                        Text("None").tag("")
                        ForEach(TradeReviewCatalog.emotions, id: \.self) { emotion in
                            Text(emotion).tag(emotion)
                        }
                    }
                }

                Section("Execution / Discipline") {
                    CompactRatingSelector(title: "Execution", value: $executionRating)
                }

                Section("Reflection") {
                    TextField("Optional note", text: $reflectionText, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
            }
            .navigationTitle("Quick Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(
                                exitEmotion.isEmpty ? nil : exitEmotion,
                                executionRating > 0 ? executionRating : nil
                            )
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("postTradeReflection.sheet")
    }
}
