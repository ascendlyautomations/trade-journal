import SwiftUI

/// Optional lightweight psychology capture after saving a trade.
struct PostTradeReflectionSheet: View {
    let trade: Trade
    let onSave: (PostTradePsychologySavePatch) async -> Void
    let onSkip: () -> Void

    @State private var confidenceLevel = 0
    @State private var emotionSelection = ""
    @State private var emotionCustom = ""
    @State private var exitEmotionSelection = ""
    @State private var exitEmotionCustom = ""
    @State private var executionRating = 0
    @State private var psychologyNotesText = ""
    @State private var isSaving = false

    @Environment(\.themeColors) private var colors

    private var gaps: TradeReviewCatalog.QuickReflectionPsychologyGaps {
        TradeReviewCatalog.quickReflectionGaps(for: trade)
    }

    var body: some View {
        NavigationStack {
            Form {
                if gaps.needsConviction {
                    Section {
                        TradePsychologyFormComponents.convictionSelector(
                            confidenceLevel: $confidenceLevel,
                            colors: colors
                        )
                    } header: {
                        Text("Conviction")
                    } footer: {
                        Text("How strongly you believed in the setup before entry.")
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                }

                if gaps.needsEmotionBefore {
                    TradePsychologyFormComponents.emotionPickerSection(
                        header: "Before the trade",
                        pickerLabel: "Emotion before trade",
                        selection: $emotionSelection,
                        customText: $emotionCustom,
                        accessibilityPrefix: "postTradeReflection.before"
                    )
                }

                if gaps.needsEmotionAfter {
                    TradePsychologyFormComponents.emotionPickerSection(
                        header: "After the trade",
                        pickerLabel: "Emotion after trade",
                        selection: $exitEmotionSelection,
                        customText: $exitEmotionCustom,
                        accessibilityPrefix: "postTradeReflection.after"
                    )
                }

                if gaps.needsExecutionRating {
                    TradePsychologyFormComponents.executionRatingSection(
                        rating: $executionRating,
                        accessibilityIdentifier: "postTradeReflection.executionRating"
                    )
                }

                if gaps.needsPsychologyNotes {
                    TradePsychologyFormComponents.psychologyNotesSection(
                        text: $psychologyNotesText,
                        colors: colors,
                        accessibilityIdentifier: "postTradeReflection.psychologyNotes"
                    )
                }
            }
            .listSectionSpacing(TradePsychologyFormComponents.sectionSpacing)
            .scrollDismissesKeyboard(.interactively)
            .experienceTradeTraxsFormStyle(pageBackground: false)
            .experienceScreenBackground()
            .navigationTitle("Quick Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .tint(colors.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(buildSavePatch())
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .experienceSheetChrome(detents: sheetDetents, interactiveDismiss: false)
        .experienceProtectedFormDismiss()
        .accessibilityIdentifier("postTradeReflection.sheet")
    }

    private var sheetDetents: Set<PresentationDetent> {
        let sectionCount = [
            gaps.needsConviction,
            gaps.needsEmotionBefore,
            gaps.needsEmotionAfter,
            gaps.needsExecutionRating,
            gaps.needsPsychologyNotes,
        ].filter { $0 }.count
        return sectionCount > 2 ? [.large] : [.medium]
    }

    private func buildSavePatch() -> PostTradePsychologySavePatch {
        var patch = PostTradePsychologySavePatch()

        if gaps.needsConviction, confidenceLevel > 0 {
            patch.confidence = confidenceLevel
        }
        if gaps.needsEmotionBefore {
            patch.emotion = TradeReviewCatalog.resolvedPsychologyValue(
                selection: emotionSelection,
                custom: emotionCustom
            )
        }
        if gaps.needsEmotionAfter {
            patch.exitEmotion = TradeReviewCatalog.resolvedPsychologyValue(
                selection: exitEmotionSelection,
                custom: exitEmotionCustom
            )
        }
        if gaps.needsExecutionRating, executionRating > 0 {
            patch.executionRating = executionRating
        }
        if gaps.needsPsychologyNotes {
            let trimmed = psychologyNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                patch.psychologyNotes = trimmed
            }
        }

        return patch
    }
}