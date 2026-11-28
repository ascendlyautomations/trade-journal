import Foundation

nonisolated protocol AICoachConversationRepository: Sendable {
    func loadConversations() async throws -> [AICoachConversationSummary]
    func loadMessages(conversationID: AICoachConversationID) async throws -> [AICoachConversationMessage]
    func ensureGeneralTradeConversation() async throws -> AICoachConversationSummary
    func persistMessages(
        conversationID: AICoachConversationID,
        messages: [AICoachConversationMessage]
    ) async throws
}

nonisolated struct DefaultAICoachConversationRepository: AICoachConversationRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding

    private static let conversationTable = "ai_coach_conversations"
    private static let messageTable = "ai_coach_messages"

    init(supabase: SupabaseInfrastructure, session: any SessionProviding) {
        self.supabase = supabase
        self.session = session
    }

    func loadConversations() async throws -> [AICoachConversationSummary] {
        guard await session.currentUserID != nil else { return [] }
        do {
            let rows: [AICoachConversationRow] = try await supabase.database.select(
                AICoachConversationRow.self,
                from: Self.conversationTable,
                query: [
                    SupabaseQuery.select("id,kind,trade_id,title,scope_label,scope_fingerprint,facts_hash,last_message_preview,last_message_at,created_at"),
                    URLQueryItem(name: "order", value: "last_message_at.desc"),
                ]
            )
            return rows.compactMap { $0.toSummary() }
        } catch {
            if Self.isMissingTableError(error) { return [] }
            throw error
        }
    }

    func loadMessages(conversationID: AICoachConversationID) async throws -> [AICoachConversationMessage] {
        guard await session.currentUserID != nil else { return [] }
        do {
            let rows: [AICoachMessageRow] = try await supabase.database.select(
                AICoachMessageRow.self,
                from: Self.messageTable,
                query: [
                    SupabaseQuery.select("id,role,content,prompt_key,client_message_id,created_at"),
                    SupabaseQuery.eq("conversation_id", conversationID.rawValue),
                    URLQueryItem(name: "order", value: "created_at.asc"),
                ]
            )
            return rows.map { $0.toDomain() }
        } catch {
            if Self.isMissingTableError(error) { return [] }
            throw error
        }
    }

    func ensureGeneralTradeConversation() async throws -> AICoachConversationSummary {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        if let existing = try await loadConversations().first(where: { $0.kind == .generalTrade }) {
            return existing
        }
        let insert = AICoachConversationInsert(
            id: UUID().uuidString,
            user_id: userID.rawValue,
            kind: AICoachConversationKind.generalTrade.rawValue,
            trade_id: nil,
            title: "General Trade AI",
            scope_label: nil,
            scope_fingerprint: nil,
            facts_hash: nil
        )
        try await insertConversation(insert)
        return AICoachConversationSummary(
            id: AICoachConversationID(insert.id),
            kind: .generalTrade,
            title: "General Trade AI",
            scopeLabel: nil,
            scopeFingerprint: nil,
            factsHash: nil,
            tradeID: nil,
            lastMessagePreview: nil,
            lastMessageAt: Date()
        )
    }

    func persistMessages(
        conversationID: AICoachConversationID,
        messages: [AICoachConversationMessage]
    ) async throws {
        guard !messages.isEmpty else { return }
        guard let userID = await session.currentUserID else { return }
        let rows = messages.map { message in
            AICoachMessageInsert(
                id: message.id.uuidString,
                conversation_id: conversationID.rawValue,
                user_id: userID.rawValue,
                role: message.role.rawValue,
                content: message.content,
                prompt_key: message.promptKey,
                client_message_id: message.id.uuidString
            )
        }
        let payload = try JSONEncoder().encode(rows)
        do {
            try await supabase.database.insertJSON(payload, into: Self.messageTable)
        } catch {
            if Self.isMissingTableError(error) { return }
            if Self.isDuplicateClientIDError(error) { return }
            throw error
        }
    }

    private func insertConversation(_ row: AICoachConversationInsert) async throws {
        do {
            let payload = try JSONEncoder().encode([row])
            try await supabase.database.insertJSON(payload, into: Self.conversationTable)
        } catch {
            if Self.isMissingTableError(error) { return }
            if Self.isDuplicateConversationError(error) { return }
            throw error
        }
    }

    private static func isMissingTableError(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("ai_coach_conversations") || text.contains("ai_coach_messages")
    }

    private static func isDuplicateClientIDError(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("ai_coach_messages_client_id_uidx") || text.contains("duplicate")
    }

    private static func isDuplicateConversationError(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("ai_coach_conversations_general_user_uidx")
            || text.contains("ai_coach_conversations_trade_user_uidx")
            || text.contains("duplicate")
    }
}

private nonisolated struct AICoachConversationRow: Decodable {
    var id: String
    var kind: String
    var trade_id: String?
    var title: String?
    var scope_label: String?
    var scope_fingerprint: String?
    var facts_hash: String?
    var last_message_preview: String?
    var last_message_at: String?

    func toSummary() -> AICoachConversationSummary? {
        guard let kind = AICoachConversationKind(rawValue: kind) else { return nil }
        return AICoachConversationSummary(
            id: AICoachConversationID(id),
            kind: kind,
            title: title ?? kind.displayTitle,
            scopeLabel: scope_label,
            scopeFingerprint: scope_fingerprint,
            factsHash: facts_hash,
            tradeID: trade_id.map { TradeID($0) },
            lastMessagePreview: last_message_preview,
            lastMessageAt: ISO8601.date(from: last_message_at) ?? Date()
        )
    }
}

private nonisolated struct AICoachMessageRow: Decodable {
    var id: String
    var role: String
    var content: String
    var prompt_key: String?
    var client_message_id: String?
    var created_at: String?

    func toDomain() -> AICoachConversationMessage {
        let messageID = UUID(uuidString: client_message_id ?? id) ?? UUID(uuidString: id) ?? UUID()
        return AICoachConversationMessage(
            id: messageID,
            role: AICoachConversationRole(rawValue: role) ?? .assistant,
            content: content,
            promptKey: prompt_key,
            createdAt: ISO8601.date(from: created_at) ?? Date()
        )
    }
}

private nonisolated struct AICoachConversationInsert: Encodable {
    var id: String
    var user_id: String
    var kind: String
    var trade_id: String?
    var title: String?
    var scope_label: String?
    var scope_fingerprint: String?
    var facts_hash: String?

    func toSummary() -> AICoachConversationSummary? {
        guard let kind = AICoachConversationKind(rawValue: kind) else { return nil }
        return AICoachConversationSummary(
            id: AICoachConversationID(id),
            kind: kind,
            title: title ?? kind.displayTitle,
            scopeLabel: scope_label,
            scopeFingerprint: scope_fingerprint,
            factsHash: facts_hash,
            tradeID: trade_id.map { TradeID($0) },
            lastMessagePreview: nil,
            lastMessageAt: Date()
        )
    }
}

private nonisolated struct AICoachMessageInsert: Encodable {
    var id: String
    var conversation_id: String
    var user_id: String
    var role: String
    var content: String
    var prompt_key: String?
    var client_message_id: String
}