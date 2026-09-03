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
        emotion: String,
        followedPlan: Bool,
        marketCondition: String,
        psychologyNotes: String
    ) -> Bool {
        confidence > 0
            || !emotion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || followedPlan
            || !marketCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !psychologyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func psychologySummary(
        confidence: Int,
        emotion: String,
        followedPlan: Bool,
        marketCondition: String,
        psychologyNotes: String
    ) -> String {
        guard hasPsychologyDetails(
            confidence: confidence,
            emotion: emotion,
            followedPlan: followedPlan,
            marketCondition: marketCondition,
            psychologyNotes: psychologyNotes
        ) else {
            return "Add psychology details"
        }

        var parts: [String] = []
        if confidence > 0 {
            parts.append("Conviction \(confidence)/5")
        }
        let trimmedEmotion = emotion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmotion.isEmpty {
            parts.append(trimmedEmotion)
        }
        let trimmedMarket = marketCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMarket.isEmpty {
            parts.append(trimmedMarket)
        }
        if followedPlan {
            parts.append("Followed plan")
        }

        if parts.isEmpty {
            let trimmedNotes = psychologyNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNotes.count > 48 {
                return String(trimmedNotes.prefix(45)) + "…"
            }
            return trimmedNotes
        }

        let joined = parts.joined(separator: " • ")
        if joined.count > 64 {
            return String(joined.prefix(61)) + "…"
        }
        return joined
    }
}
