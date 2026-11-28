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

nonisolated struct TradeAIAttachment: Hashable, Codable, Sendable {
    var kind: String
    var url: String
    var storagePath: String?
    var tradeID: TradeID?

    init(
        kind: String = "uploaded_image",
        url: String = "",
        storagePath: String? = nil,
        tradeID: TradeID? = nil
    ) {
        self.kind = kind
        self.url = url
        self.storagePath = storagePath
        self.tradeID = tradeID
    }

    static func attachedTrade(_ tradeID: TradeID) -> TradeAIAttachment {
        TradeAIAttachment(kind: "trade", tradeID: tradeID)
    }
}

nonisolated struct TradeAIMessage: Hashable, Identifiable, Codable, Sendable {
    var id: String
    var role: TradeAIMessageRole
    /// Display text (preset title or custom question for user; coach reply for assistant).
    var content: String
    /// Preset id, `"custom"`, or nil for assistant rows.
    var promptKey: String?
    var attachments: [TradeAIAttachment]
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        role: TradeAIMessageRole,
        content: String,
        promptKey: String? = nil,
        attachments: [TradeAIAttachment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.promptKey = promptKey
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

nonisolated struct TradeAIUploadAttachmentRequest: Sendable {
    var imageData: Data
    var mimeType: String
    var conversationID: AIConversationID?
}

nonisolated struct TradeAICreateConversationRequest: Sendable {
    var title: String
    var scope: TradeAIPortfolioScope
}

nonisolated struct TradeAICreateConversationResponse: Sendable {
    var conversationID: AIConversationID
    var kind: String
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

    /// Full-screen Trade AI conversation — one tap sends via existing preset / coach prompts.
    static let conversationStarters: [TradeAISuggestedPrompt] = [
        .init(id: "analyze", title: "Analyze this trade", prompt: "Analyze this trade"),
        .init(
            id: "mistakes",
            title: "What could I have done better?",
            prompt: "What could I have done better?"
        ),
        .init(
            id: "execution",
            title: "How was my entry and exit?",
            prompt: "How was my entry and exit?"
        ),
        .init(
            id: "plan",
            title: "Did I follow my trading rules?",
            prompt: "Did I follow my trading rules?"
        ),
        .init(
            id: "emotional",
            title: "Analyze my trading psychology",
            prompt: "Analyze my trading psychology"
        ),
    ]

    static func prompt(id: String) -> TradeAISuggestedPrompt? {
        all.first { $0.id == id }
            ?? conversationStarters.first { $0.id == id }
    }
}

nonisolated struct TradeAIAnalyzeRequest: Sendable {
    var context: TradeAIContext
    /// Full turn list including the latest user message (web contract).
    var messages: [TradeAIMessage]
}

nonisolated struct TradeAIAnalyzeResponse: Sendable {
    var reply: String
    /// False for HTTP/API failures shown in the thread but not saved as analyses.
    var shouldPersist: Bool = true
    /// BFF failure `code` when analysis did not succeed (`nil` on success).
    var backendCode: String? = nil
}

nonisolated struct AIConversationID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct TradeAIConversationMeta: Hashable, Sendable {
    var id: AIConversationID
    var kind: String
    var tradeID: TradeID?
    var title: String?
    /// Restored analytics scope for Psychology Coach threads (Messages reopen).
    var psychologyFactsSnapshot: PsychologyCoachFacts?
}

nonisolated struct TradeAIConversationInboxItem: Hashable, Sendable, Identifiable {
    var id: AIConversationID
    var kind: String
    var tradeID: TradeID?
    var title: String?
    var preview: String?
    var lastMessageAt: Date?
}

nonisolated struct TradeAITradeTurnRequest: Sendable {
    var tradeID: TradeID
    var conversationID: AIConversationID?
    var userMessage: TradeAIMessage
    var apiMessages: [TradeAIMessage]
}

nonisolated struct TradeAIPortfolioTurnRequest: Sendable {
    var conversationID: AIConversationID?
    var scope: TradeAIPortfolioScope
    var title: String?
    var userMessage: TradeAIMessage
    var apiMessages: [TradeAIMessage]
}

nonisolated struct TradeAIPortfolioScope: Hashable, Codable, Sendable {
    var preset: String
    var accountIds: [String]?
    var startDate: String?
    var endDate: String?
}

nonisolated struct TradeAITurnResponse: Sendable {
    var reply: String
    var conversationID: AIConversationID
    var userMessageID: String
    var assistantMessageID: String
    var shouldPersist: Bool
    var persistError: String?
    var backendCode: String?
    /// False when the BFF did not return decodable coach copy (do not show as assistant turn).
    var analysisSucceeded: Bool = true
}

nonisolated struct TradeAIPersistTurnRequest: Sendable {
    var conversationID: AIConversationID
    var userMessage: TradeAIMessage
    var assistantMessage: TradeAIMessage
}

/// Parsed coach sections for premium Trade AI rendering.
nonisolated struct TradeAICoachSections: Hashable, Sendable {
    var verdict: String?
    var biggestInsight: String?
    var strengths: [String]
    var keyImprovements: [String]
    var nextTradeFocus: String?

    var isStructured: Bool {
        verdict != nil
            || biggestInsight != nil
            || !strengths.isEmpty
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
        var strengths: [String] = []
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
                verdict = appendBlock(verdict, line)
            case .biggestInsight:
                insight = appendBlock(insight, line)
            case .strengths:
                strengths.append(contentsOf: listLines(from: line))
            case .keyImprovements:
                improvements.append(contentsOf: listLines(from: line))
            case .nextTradeFocus:
                nextFocus = appendBlock(nextFocus, line)
            }
        }

        let sections = TradeAICoachSections(
            verdict: trim(verdict),
            biggestInsight: trim(insight),
            strengths: Array(strengths.prefix(5)),
            keyImprovements: Array(improvements.prefix(5)),
            nextTradeFocus: trim(nextFocus)
        )
        return sections.isStructured ? sections : nil
    }

    private enum SectionKey: String {
        case verdict
        case biggestInsight
        case strengths
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
            case "verdict", "final verdict":
                return .verdict
            case "biggest insight", "biggestinsight", "summary":
                return .biggestInsight
            case "strengths", "what went well":
                return .strengths
            case "key improvements", "keyimprovements", "improvements",
                 "areas for improvement", "recommendations":
                return .keyImprovements
            case "behavior observed":
                return .biggestInsight
            case "next trade focus", "nexttradefocus", "next focus":
                return .nextTradeFocus
            default:
                return nil
            }
        }
    }

    private static func listLines(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil {
            return [trimmed]
        }

        let cleaned = trimmed
            .replacingOccurrences(of: #"^[-*•]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? [] : [cleaned]
    }

    private static func appendBlock(_ existing: String?, _ line: String) -> String {
        if let existing, !existing.isEmpty {
            return existing + "\n\n" + line
        }
        return line
    }

    private static func trim(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum GeneralTradeAIAPIMessageBuilder {
    /// Portfolio turns use display text only, not single-trade preset expansion.
    static func messagesForAPI(from messages: [TradeAIMessage]) -> [TradeAIMessage] {
        messages
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
                attachments: message.attachments,
                createdAt: message.createdAt
            )
        }
    }
}

nonisolated struct GeneralTradeAIMessage: Hashable, Codable, Sendable {
    var role: String
    var content: String
}

nonisolated struct GeneralTradeAIRequest: Sendable {
    var question: String
    var messages: [GeneralTradeAIMessage]
}

nonisolated struct GeneralTradeAIResponse: Sendable {
    var reply: String
}
