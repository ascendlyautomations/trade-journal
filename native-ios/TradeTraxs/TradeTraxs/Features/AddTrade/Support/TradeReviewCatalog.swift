import Foundation

/// Web `InputTradeForm` trade review + psychology option lists.
nonisolated enum TradeReviewCatalog {
    static let customTimeframeToken = "Custom"

    static let timeframePresets = [
        "15s", "30s", "1m", "2m", "3m", "5m", "15m", "30m", "1hr", "2hr", "4hr",
    ]

    static let timeframeOptions: [String] = timeframePresets + [customTimeframeToken]

    static let emotions = [
        "Confident",
        "Calm",
        "Focused",
        "Fearful",
        "FOMO",
        "Overconfident",
        "Hesitant",
        "Frustrated",
    ]

    static let marketConditions = [
        "Trending",
        "Strong Trend",
        "Ranging",
        "Choppy",
        "Low Volume",
        "High Volume",
        "News Driven",
        "Volatile",
    ]

    static let customPsychologyToken = "Custom..."

    static var emotionOptions: [String] { emotions + [customPsychologyToken] }

    static var marketConditionOptions: [String] { marketConditions + [customPsychologyToken] }

    static func resolvedPsychologyValue(selection: String, custom: String) -> String? {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return nil }
        if trimmedSelection == customPsychologyToken {
            let trimmedCustom = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCustom.isEmpty ? nil : trimmedCustom
        }
        return trimmedSelection
    }

    static func psychologyPickerState(for stored: String?, presets: [String]) -> (selection: String, custom: String) {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return ("", "") }
        if presets.contains(trimmed) {
            return (trimmed, "")
        }
        return (customPsychologyToken, trimmed)
    }

    static func psychologyPickerStateFromDraft(
        pickerSelection: String,
        customText: String,
        presets: [String]
    ) -> (selection: String, custom: String) {
        let selection = pickerSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection == customPsychologyToken {
            return (selection, custom)
        }
        if !selection.isEmpty {
            if presets.contains(selection) {
                return (selection, "")
            }
            return (customPsychologyToken, selection)
        }
        if !custom.isEmpty {
            return (customPsychologyToken, custom)
        }
        return ("", "")
    }

    static func resolvedTimeframe(selection: String, custom: String) -> String? {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return nil }
        if trimmedSelection == customTimeframeToken {
            let trimmedCustom = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCustom.isEmpty ? nil : trimmedCustom
        }
        return trimmedSelection
    }

    static func timeframeSelection(for stored: String?) -> (selection: String, custom: String) {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return ("", "") }
        if timeframePresets.contains(trimmed) {
            return (trimmed, "")
        }
        return (customTimeframeToken, trimmed)
    }

    static func hasPsychologyDetails(
        confidence: Int,
        emotionBefore: String,
        emotionAfter: String,
        executionRating: Int,
        psychologyNotes: String
    ) -> Bool {
        confidence > 0
            || !emotionBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !emotionAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || executionRating > 0
            || !psychologyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func psychologySummary(
        confidence: Int,
        emotionBefore: String,
        emotionAfter: String,
        executionRating: Int,
        psychologyNotes: String
    ) -> String {
        guard hasPsychologyDetails(
            confidence: confidence,
            emotionBefore: emotionBefore,
            emotionAfter: emotionAfter,
            executionRating: executionRating,
            psychologyNotes: psychologyNotes
        ) else {
            return "Add psychology details"
        }

        var parts: [String] = []
        if confidence > 0 {
            parts.append("Conviction \(confidence)/5")
        }
        let before = emotionBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        if !before.isEmpty {
            parts.append("Before: \(before)")
        }
        let after = emotionAfter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty {
            parts.append("After: \(after)")
        }
        if executionRating > 0 {
            parts.append("Exec \(executionRating)/5")
        }

        if parts.isEmpty {
            let trimmedNotes = psychologyNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNotes.count > 48 {
                return String(trimmedNotes.prefix(45)) + "…"
            }
            return trimmedNotes
        }

        let joined = parts.joined(separator: " • ")
        if joined.count > 72 {
            return String(joined.prefix(69)) + "…"
        }
        return joined
    }

  /// Appends a post-trade reflection line to psychology notes without touching journal notes.
    static func mergePsychologyReflectionNote(existing: String?, newNote: String) -> String? {
        let trimmed = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? existing : nil }
        let prior = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prior.isEmpty { return trimmed }
        if prior.contains(trimmed) { return prior }
        return prior + "\n\n" + trimmed
    }

    struct QuickReflectionPsychologyGaps: Sendable {
        var needsConviction: Bool
        var needsEmotionBefore: Bool
        var needsEmotionAfter: Bool
        var needsExecutionRating: Bool
        var needsPsychologyNotes: Bool

        var hasAnyGap: Bool {
            needsConviction
                || needsEmotionBefore
                || needsEmotionAfter
                || needsExecutionRating
                || needsPsychologyNotes
        }
    }

    static func quickReflectionGaps(for trade: Trade) -> QuickReflectionPsychologyGaps {
        QuickReflectionPsychologyGaps(
            needsConviction: (trade.confidence ?? 0) < 1,
            needsEmotionBefore: trade.emotion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
            needsEmotionAfter: trade.exitEmotion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
            needsExecutionRating: (trade.executionRating ?? 0) < 1,
            needsPsychologyNotes: trade.psychologyNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        )
    }

    /// Quick reflection when every Add Trade psychology field is already captured.
    static func quickReflectionIsRedundant(for trade: Trade) -> Bool {
        !quickReflectionGaps(for: trade).hasAnyGap
    }

    static func applyPsychologyPatch(_ patch: PostTradePsychologySavePatch, to draft: inout TradeDraft) {
        if let confidence = patch.confidence, confidence > 0 {
            draft.confidence = confidence
        }
        if let emotion = patch.emotion?.trimmingCharacters(in: .whitespacesAndNewlines), !emotion.isEmpty {
            draft.emotion = emotion
        }
        if let exitEmotion = patch.exitEmotion?.trimmingCharacters(in: .whitespacesAndNewlines), !exitEmotion.isEmpty {
            draft.exitEmotion = exitEmotion
        }
        if let executionRating = patch.executionRating, executionRating > 0 {
            draft.executionRating = executionRating
        }
        if let psychologyNotes = patch.psychologyNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !psychologyNotes.isEmpty
        {
            draft.psychologyNotes = psychologyNotes
        }
    }
}
