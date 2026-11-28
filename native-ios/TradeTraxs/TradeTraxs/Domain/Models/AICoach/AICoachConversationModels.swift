import Foundation

nonisolated enum AICoachConversationKind: String, Hashable, Codable, Sendable, CaseIterable {
    case trade
    case generalTrade = "general_trade"
    case psychology

    var displayTitle: String {
        switch self {
        case .trade: return "Trade AI"
        case .generalTrade: return "General Trade AI"
        case .psychology: return "Psychology Coach"
        }
    }

    var iconSystemName: String {
        switch self {
        case .trade, .generalTrade: return "brain.head.profile"
        case .psychology: return "heart.text.square"
        }
    }
}

nonisolated struct AICoachConversationID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct AICoachConversationSummary: Identifiable, Hashable, Sendable {
    var id: AICoachConversationID
    var kind: AICoachConversationKind
    var title: String
    var scopeLabel: String?
    var scopeFingerprint: String?
    var factsHash: String?
    var tradeID: TradeID?
    var lastMessagePreview: String?
    var lastMessageAt: Date
}

nonisolated struct AICoachConversationMessage: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var role: AICoachConversationRole
    var content: String
    var promptKey: String?
    var createdAt: Date?

    init(
        id: UUID = UUID(),
        role: AICoachConversationRole,
        content: String,
        promptKey: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.promptKey = promptKey
        self.createdAt = createdAt
    }
}

nonisolated enum AICoachConversationRole: String, Hashable, Codable, Sendable {
    case user
    case assistant
}