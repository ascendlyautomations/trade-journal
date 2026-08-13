import Foundation

/// Extensible analysis context for Trade AI.
///
/// Today the primary payload is the selected trade. Future sources (screenshots,
/// clips, account stats, strategy history, prior trades, journal notes) attach
/// here without changing the Trade Detail UI contract.
nonisolated struct TradeAIContext: Hashable, Sendable {
    var tradeID: TradeID
    /// Structured trade fields forwarded to the shared BFF `/api/analyze-trade`.
    var tradePayload: TradeAITradePayload
    /// Optional journal notes already loaded by Trade Detail.
    var journalNotes: [String] = []
    /// Future: screenshot / uploaded image URLs or storage paths.
    var mediaAttachments: [TradeAIMediaAttachment] = []
    /// Future: linked clip IDs.
    var linkedClipIDs: [ReelID] = []
    /// Future: opaque account / strategy aggregates prepared by the feature layer.
    var accountStatisticsSummary: String? = nil
    var strategyHistorySummary: String? = nil
    var previousTradesSummary: String? = nil
}

/// Snake_case trade shape expected by web + native analyze-trade BFF.
nonisolated struct TradeAITradePayload: Hashable, Codable, Sendable {
    var id: String
    var ticker: String?
    var direction: String?
    var pnl: String?
    var rr: String?
    var entry_price: String?
    var exit_price: String?
    var entry_time: String?
    var exit_time: String?
    var session: String?
    var strategy: String?
    var mode: String?
    var contracts: String?
    var notes: String?
    var public_description: String?
    var user_id: String?
}

nonisolated struct TradeAIMediaAttachment: Hashable, Codable, Sendable {
    var kind: Kind
    var reference: String

    enum Kind: String, Hashable, Codable, Sendable {
        case screenshot
        case uploadedImage
        case clipThumbnail
    }
}

nonisolated enum TradeAIMessageRole: String, Hashable, Codable, Sendable {
    case user
    case assistant
}

nonisolated struct TradeAIMessage: Hashable, Identifiable, Codable, Sendable {
    var id: String
    var role: TradeAIMessageRole
    /// Display text (preset title or custom question for user; coach reply for assistant).
    var content: String
    /// Preset id, `"custom"`, or nil for assistant rows.
    var promptKey: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        role: TradeAIMessageRole,
        content: String,
        promptKey: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.promptKey = promptKey
        self.createdAt = createdAt
    }
}

nonisolated struct TradeAISuggestedPrompt: Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var prompt: String
}

nonisolated enum TradeAISuggestedPrompts {
    /// Primary analysis-menu options (native Menu / Analyze flow).
    static let all: [TradeAISuggestedPrompt] = [
        .init(id: "analyze", title: "Analyze this trade", prompt: "Analyze this trade"),
        .init(id: "winning", title: "Compare to my winning trades", prompt: "Compare to my winning trades"),
        .init(id: "losing", title: "Compare to my losing trades", prompt: "Compare to my losing trades"),
        .init(id: "mistakes", title: "Find my biggest mistakes", prompt: "Find my biggest mistakes"),
        .init(id: "risk", title: "Review my risk management", prompt: "Review my risk management"),
        .init(id: "execution", title: "Evaluate my execution", prompt: "Evaluate my execution"),
        .init(id: "emotional", title: "Was this emotional trading?", prompt: "Was this emotional trading?"),
        .init(id: "plan", title: "Did I follow my trading plan?", prompt: "Did I follow my trading plan?"),
        .init(id: "journal", title: "Generate a journal summary", prompt: "Generate a journal summary"),
        .init(id: "actions", title: "Give me 3 action items", prompt: "Give me 3 action items"),
    ]

    static var `default`: TradeAISuggestedPrompt { all[0] }

    static func prompt(id: String) -> TradeAISuggestedPrompt? {
        all.first { $0.id == id }
    }
}

nonisolated struct TradeAIAnalyzeRequest: Sendable {
    var context: TradeAIContext
    /// Full turn list including the latest user message (web contract).
    var messages: [TradeAIMessage]
}

nonisolated struct TradeAIAnalyzeResponse: Sendable {
    var reply: String
}

/// Parsed coach sections for premium Trade AI rendering.
nonisolated struct TradeAICoachSections: Hashable, Sendable {
    var verdict: String?
    var biggestInsight: String?
    var keyImprovements: [String]
    var nextTradeFocus: String?

    var isStructured: Bool {
        verdict != nil
            || biggestInsight != nil
            || !keyImprovements.isEmpty
            || nextTradeFocus != nil
    }
}

nonisolated enum TradeAICoachResponseParser {
    static func parse(_ content: String) -> TradeAICoachSections? {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var verdict: String?
        var insight: String?
        var improvements: [String] = []
        var nextFocus: String?
        var current: SectionKey?

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let key = SectionKey.match(line) {
                current = key
                continue
            }
            guard let current, !line.isEmpty else { continue }

            switch current {
            case .verdict:
                verdict = append(verdict, line)
            case .biggestInsight:
                insight = append(insight, line)
            case .keyImprovements:
                improvements.append(contentsOf: bulletLines(from: line))
            case .nextTradeFocus:
                nextFocus = append(nextFocus, line)
            }
        }

        let sections = TradeAICoachSections(
            verdict: trim(verdict),
            biggestInsight: trim(insight),
            keyImprovements: Array(improvements.prefix(3)),
            nextTradeFocus: trim(nextFocus)
        )
        return sections.isStructured ? sections : nil
    }

    private enum SectionKey: String {
        case verdict
        case biggestInsight
        case keyImprovements
        case nextTradeFocus

        static func match(_ line: String) -> SectionKey? {
            let stripped = line
                .replacingOccurrences(of: #"^#{1,3}\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\*\*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\*\*:?$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch stripped {
            case "verdict":
                return .verdict
            case "biggest insight", "biggestinsight":
                return .biggestInsight
            case "key improvements", "keyimprovements", "improvements":
                return .keyImprovements
            case "next trade focus", "nexttradefocus", "next focus":
                return .nextTradeFocus
            default:
                return nil
            }
        }
    }

    private static func bulletLines(from line: String) -> [String] {
        let cleaned = line
            .replacingOccurrences(of: #"^[-*•]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+[\.\)]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? [] : [cleaned]
    }

    private static func append(_ existing: String?, _ line: String) -> String {
        if let existing, !existing.isEmpty {
            return existing + " " + line
        }
        return line
    }

    private static func trim(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum TradeAIAPIMessageBuilder {
    /// Expands stored display turns into specialized coach user content for `/api/analyze-trade`.
    static func messagesForAPI(from messages: [TradeAIMessage]) -> [TradeAIMessage] {
        messages.map { message in
            guard message.role == .user else { return message }
            let apiContent: String
            if let key = message.promptKey,
               key != "custom",
               let preset = TradeAISuggestedPrompts.prompt(id: key)
            {
                apiContent = TradeAICoachPrompts.apiContent(for: preset)
            } else {
                apiContent = TradeAICoachPrompts.apiContentForCustomQuestion(message.content)
            }
            return TradeAIMessage(
                id: message.id,
                role: .user,
                content: apiContent,
                promptKey: message.promptKey,
                createdAt: message.createdAt
            )
        }
    }
}
