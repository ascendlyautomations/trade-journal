import Foundation

nonisolated struct DefaultMessageRepository: MessageRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func conversations(page: PageRequest) async throws -> CursorPage<Conversation> {
        let rows: [MessageDTO.Conversation] = try await supabase.database.select(
            MessageDTO.Conversation.self,
            from: "conversations",
            query: SupabaseQuery.page(page, orderColumn: "updated_at") + [
                SupabaseQuery.select("*"),
            ]
        )
        let items = rows.compactMap(mapConversation)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) {
                $0.updated_at ?? $0.created_at
            }
        )
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        let dto: MessageDTO.Conversation = try await supabase.database.selectOne(
            MessageDTO.Conversation.self,
            from: "conversations",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        )
        guard let mapped = mapConversation(dto) else {
            throw AppError.domain(.notFound(entity: "conversation", id: id.rawValue))
        }
        return mapped
    }

    func messages(
        in conversationID: ConversationID,
        page: PageRequest
    ) async throws -> CursorPage<Message> {
        let rows: [MessageDTO.Message] = try await supabase.database.select(
            MessageDTO.Message.self,
            from: "messages",
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("conversation_id", conversationID.rawValue),
            ]
        )
        let items = try rows.map(MessageMapper.mapToDomain)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.created_at }
        )
    }

    func send(_ message: Message) async throws -> Message {
        struct Body: Encodable {
            var conversation_id: String
            var sender_id: String
            var content: String?
        }
        let body = Body(
            conversation_id: message.conversationID.rawValue,
            sender_id: message.senderProfileID.rawValue,
            content: message.body
        )
        let dto: MessageDTO.Message = try await supabase.database.insert(
            body,
            into: "messages",
            returning: MessageDTO.Message.self
        )
        return try MessageMapper.mapToDomain(dto)
    }

    func markRead(conversationID: ConversationID, upTo messageID: MessageID) async throws {
        struct Params: Encodable {
            var p_conversation_id: String
            var p_message_id: String
        }
        let data = try JSONEncoder().encode(
            Params(p_conversation_id: conversationID.rawValue, p_message_id: messageID.rawValue)
        )
        _ = try await supabase.database.rpcData(
            functionName: "mark_conversation_read",
            parametersJSON: data
        )
    }

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        struct Body: Encodable, Decodable {
            var participant_ids: [String]
        }
        let body = Body(participant_ids: participantIDs.map(\.rawValue))
        let dto: MessageDTO.Conversation = try await supabase.database.insert(
            body,
            into: "conversations",
            returning: MessageDTO.Conversation.self
        )
        guard let mapped = mapConversation(dto) else {
            throw AppError.unknown(message: "Failed to create conversation")
        }
        return mapped
    }

    private func mapConversation(_ dto: MessageDTO.Conversation) -> Conversation? {
        guard let id = dto.id else { return nil }
        return Conversation(
            id: ConversationID(id),
            participantProfileIDs: (dto.participant_ids ?? []).map { ProfileID($0) },
            title: nil,
            lastMessagePreview: dto.last_message_preview,
            lastMessageAt: ISO8601.date(from: dto.last_message_at),
            unreadCount: dto.unread_count ?? 0,
            isMuted: false,
            updatedAt: ISO8601.date(from: dto.updated_at)
                ?? ISO8601.date(from: dto.created_at)
                ?? Date()
        )
    }
}
