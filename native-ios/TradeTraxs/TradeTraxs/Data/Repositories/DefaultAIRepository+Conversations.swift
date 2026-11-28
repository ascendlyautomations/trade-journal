import Foundation

extension DefaultAIRepository {
    func uploadAICoachAttachment(
        _ request: TradeAIUploadAttachmentRequest
    ) async throws -> TradeAIAttachment {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        var parts: [MultipartFormData.Part] = [
            .init(
                name: "file",
                fileName: "attachment.jpg",
                mimeType: request.mimeType,
                data: request.imageData
            ),
        ]
        if let conversationID = request.conversationID {
            parts.append(
                .init(
                    name: "conversationId",
                    data: Data(conversationID.rawValue.utf8)
                )
            )
        }

        let form = MultipartFormData(parts: parts)
        let encoded = form.encode()

        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/upload-attachment",
            method: .post,
            headers: ["Content-Type": encoded.contentType],
            body: encoded.data,
            requiresAuthentication: true
        )

        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Could not upload this image.")
        }

        let decoded = try JSONDecoder().decode(
            AICoachAttachmentUploadBFFResponse.self,
            from: response.data
        )
        guard let row = decoded.attachment, let url = row.url, !url.isEmpty else {
            throw AppError.unknown(message: "Could not upload this image.")
        }
        return TradeAIAttachment(
            kind: row.kind ?? "uploaded_image",
            url: url,
            storagePath: row.storagePath ?? row.storage_path
        )
    }

    func createGeneralTradeConversation(
        _ request: TradeAICreateConversationRequest
    ) async throws -> TradeAICreateConversationResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let body = CreateConversationBFFBody(
            kind: "general_trade",
            title: request.title,
            scope: PortfolioScopeBFF(
                preset: request.scope.preset,
                accountIds: request.scope.accountIds,
                startDate: request.scope.startDate,
                endDate: request.scope.endDate
            )
        )
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/conversations/create",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        let decoded = try JSONDecoder().decode(
            AICoachCreateConversationBFFResponse.self,
            from: response.data
        )
        guard let id = decoded.conversationId else {
            throw AppError.unknown(message: "Could not start this conversation.")
        }
        return TradeAICreateConversationResponse(
            conversationID: AIConversationID(id),
            kind: decoded.kind ?? "general_trade"
        )
    }
    func analyzeTradeTurn(_ request: TradeAITradeTurnRequest) async throws -> TradeAITurnResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let body = TradeTurnBFFBody(
            tradeId: request.tradeID.rawValue,
            conversationId: request.conversationID?.rawValue,
            userMessage: TradeTurnBFFUserMessage(
                id: request.userMessage.id,
                displayContent: request.userMessage.content,
                openaiContent: request.apiMessages.last(where: { $0.id == request.userMessage.id })?.content
                    ?? request.userMessage.content,
                promptKey: request.userMessage.promptKey,
                attachments: request.userMessage.attachments.map(TradeTurnBFFAttachment.init),
                createdAt: ISO8601.string(from: request.userMessage.createdAt)
            ),
            assistantMessageId: UUID().uuidString,
            messages: request.apiMessages.map {
                TradeTurnBFFWireMessage(
                    role: $0.role.rawValue,
                    content: $0.content,
                    attachments: $0.attachments.isEmpty ? nil : $0.attachments.map(TradeTurnBFFAttachment.init)
                )
            }
        )

        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/trade-turn",
            method: .post,
            body: data,
            requiresAuthentication: true,
            acceptsNonSuccessStatusCodes: true
        )

        TradeAITrace.tradeTurnResponse(status: response.statusCode, byteCount: response.data.count)
        return TradeAITurnHTTPMapping.map(statusCode: response.statusCode, data: response.data)
    }

    func analyzePortfolioTurn(_ request: TradeAIPortfolioTurnRequest) async throws -> TradeAITurnResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let body = PortfolioTurnBFFBody(
            conversationId: request.conversationID?.rawValue,
            createConversation: request.conversationID == nil,
            title: request.title,
            scope: PortfolioScopeBFF(
                preset: request.scope.preset,
                accountIds: request.scope.accountIds,
                startDate: request.scope.startDate,
                endDate: request.scope.endDate
            ),
            userMessage: TradeTurnBFFUserMessage(
                id: request.userMessage.id,
                displayContent: request.userMessage.content,
                openaiContent: request.apiMessages.last(where: { $0.id == request.userMessage.id })?.content
                    ?? request.userMessage.content,
                promptKey: request.userMessage.promptKey,
                attachments: request.userMessage.attachments.map(TradeTurnBFFAttachment.init),
                createdAt: ISO8601.string(from: request.userMessage.createdAt)
            ),
            messages: request.apiMessages.map {
                TradeTurnBFFWireMessage(
                    role: $0.role.rawValue,
                    content: $0.content,
                    attachments: $0.attachments.isEmpty ? nil : $0.attachments.map(TradeTurnBFFAttachment.init)
                )
            }
        )

        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/portfolio-turn",
            method: .post,
            body: data,
            requiresAuthentication: true,
            acceptsNonSuccessStatusCodes: true
        )

        TradeAITrace.tradeTurnResponse(status: response.statusCode, byteCount: response.data.count)
        return TradeAITurnHTTPMapping.map(statusCode: response.statusCode, data: response.data)
    }

    func persistTurn(_ request: TradeAIPersistTurnRequest) async throws {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let body = PersistTurnBFFBody(
            conversationId: request.conversationID.rawValue,
            userMessage: TradeTurnBFFUserMessage(
                id: request.userMessage.id,
                displayContent: request.userMessage.content,
                openaiContent: request.userMessage.content,
                promptKey: request.userMessage.promptKey,
                attachments: request.userMessage.attachments.map(TradeTurnBFFAttachment.init),
                createdAt: ISO8601.string(from: request.userMessage.createdAt)
            ),
            assistantMessage: PersistTurnAssistantMessage(
                id: request.assistantMessage.id,
                content: request.assistantMessage.content,
                createdAt: ISO8601.string(from: request.assistantMessage.createdAt)
            )
        )

        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/persist-turn",
            method: .post,
            body: data,
            requiresAuthentication: true,
            acceptsNonSuccessStatusCodes: true
        )

        guard (200 ... 299).contains(response.statusCode) else {
            #if DEBUG
            TradeAITrace.persistTurnFailed(status: response.statusCode, byteCount: response.data.count)
            #endif
            throw AppError.unknown(message: "Could not save this conversation turn.")
        }
        #if DEBUG
        TradeAITrace.persistTurnSucceeded(status: response.statusCode, byteCount: response.data.count)
        #endif
    }

    func loadConversationMessages(
        conversationID: AIConversationID
    ) async throws -> (TradeAIConversationMeta, [TradeAIMessage]) {
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/conversations/\(conversationID.rawValue)/messages",
            method: .get,
            requiresAuthentication: true
        )

        let decoded = try JSONDecoder().decode(ConversationMessagesBFFResponse.self, from: response.data)
        #if DEBUG
        let mappedCount = (decoded.messages ?? []).count
        TradeAITrace.conversationHistoryLoaded(
            tradeScoped: false,
            status: response.statusCode,
            byteCount: response.data.count,
            decoded: true,
            messageCount: mappedCount
        )
        #endif
        guard let conversationRow = decoded.conversation else {
            throw AppError.unknown(message: "Conversation not found")
        }
        let meta = TradeAIConversationMeta(
            id: AIConversationID(conversationRow.id),
            kind: conversationRow.kind,
            tradeID: conversationRow.trade_id.flatMap { TradeID($0) },
            title: conversationRow.title,
            psychologyFactsSnapshot: AIConversationMessagesBFFDecoding.factsSnapshot(
                conversationRow
            )
        )
        let messages = (decoded.messages ?? []).compactMap { row -> TradeAIMessage? in
            guard let role = TradeAIMessageRole(rawValue: row.role ?? "") else { return nil }
            return TradeAIMessage(
                id: row.id ?? UUID().uuidString,
                role: role,
                content: role == .assistant
                    ? AIGeneratedTextNormalizer.normalize(row.content ?? "")
                    : (row.content ?? ""),
                promptKey: AIConversationMessagesBFFDecoding.promptKey(row),
                attachments: AIConversationMessagesBFFDecoding.attachments(row),
                createdAt: AIConversationMessagesBFFDecoding.createdAt(row)
                    .flatMap(ISO8601.date(from:)) ?? Date()
            )
        }
        return (meta, messages)
    }

    func loadConversationInbox(limit: Int) async throws -> [TradeAIConversationInboxItem] {
        guard let transport = supabase.transport else { return [] }
        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/conversations/inbox?limit=\(max(1, min(limit, 200)))",
            method: .get,
            requiresAuthentication: true
        )
        let decoded = try JSONDecoder().decode(ConversationInboxBFFResponse.self, from: response.data)
        return (decoded.conversations ?? []).compactMap { row in
            guard let id = row.id else { return nil }
            return TradeAIConversationInboxItem(
                id: AIConversationID(id),
                kind: row.kind ?? "trade",
                tradeID: row.trade_id.flatMap { TradeID($0) },
                title: row.title,
                preview: row.last_message_preview,
                lastMessageAt: row.last_message_at.flatMap(ISO8601.date(from:))
            )
        }
    }

    func renameAICoachConversation(id: AIConversationID, title: String) async throws {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.unknown(message: "Enter a conversation name.")
        }

        struct Body: Encodable { var title: String }
        struct Response: Decodable { var error: String?; var code: String? }

        let data = try transport.encodeJSON(Body(title: trimmed))
        let response = try await transport.send(
            host: .bff,
            path: "/api/ai/conversations/\(id.rawValue)",
            method: .patch,
            body: data,
            requiresAuthentication: true,
            acceptsNonSuccessStatusCodes: true
        )

        if (200 ... 299).contains(response.statusCode) {
            return
        }

        let decoded = try? JSONDecoder().decode(Response.self, from: response.data)
        let message = decoded?.error ?? "Could not rename this conversation."
        if response.statusCode == 404 {
            throw AppError.unknown(message: message)
        }
        throw AppError.unknown(message: message)
    }

}

// MARK: - BFF wire types

private nonisolated struct AICoachAttachmentUploadBFFResponse: Decodable, Sendable {
    struct AttachmentRow: Decodable, Sendable {
        var kind: String?
        var url: String?
        var storagePath: String?
        var storage_path: String?
    }

    var attachment: AttachmentRow?
}

private nonisolated struct AICoachCreateConversationBFFResponse: Decodable, Sendable {
    var conversationId: String?
    var kind: String?
}

private nonisolated struct TradeTurnBFFBody: Encodable, Sendable {
    var tradeId: String
    var conversationId: String?
    var userMessage: TradeTurnBFFUserMessage
    var assistantMessageId: String?
    var messages: [TradeTurnBFFWireMessage]
}

private nonisolated struct PortfolioTurnBFFBody: Encodable, Sendable {
    var conversationId: String?
    var createConversation: Bool
    var title: String?
    var scope: PortfolioScopeBFF
    var userMessage: TradeTurnBFFUserMessage
    var assistantMessageId: String?
    var messages: [TradeTurnBFFWireMessage]
}

private nonisolated struct PortfolioScopeBFF: Encodable, Sendable {
    var preset: String
    var accountIds: [String]?
    var startDate: String?
    var endDate: String?
}

private nonisolated struct CreateConversationBFFBody: Encodable, Sendable {
    var kind: String
    var title: String
    var scope: PortfolioScopeBFF
}

private nonisolated struct TradeTurnBFFUserMessage: Encodable, Sendable {
    var id: String
    var displayContent: String
    var openaiContent: String
    var promptKey: String?
    var attachments: [TradeTurnBFFAttachment]?
    var createdAt: String
}

private nonisolated struct TradeTurnBFFAttachment: Encodable, Sendable {
    var kind: String
    var url: String?
    var storagePath: String?
    var tradeId: String?

    nonisolated init(_ attachment: TradeAIAttachment) {
        kind = attachment.kind
        url = attachment.url.isEmpty ? nil : attachment.url
        storagePath = attachment.storagePath
        tradeId = attachment.tradeID?.rawValue
    }
}

private nonisolated struct TradeTurnBFFWireMessage: Encodable, Sendable {
    var role: String
    var content: String
    var attachments: [TradeTurnBFFAttachment]?
}

private nonisolated struct PersistTurnBFFBody: Encodable, Sendable {
    var conversationId: String
    var userMessage: TradeTurnBFFUserMessage
    var assistantMessage: PersistTurnAssistantMessage
}

private nonisolated struct PersistTurnAssistantMessage: Encodable, Sendable {
    var id: String
    var content: String
    var createdAt: String
}

nonisolated struct ConversationMessagesBFFResponse: Decodable, Sendable {
    struct Conversation: Decodable, Sendable {
        var id: String
        var kind: String
        var trade_id: String?
        var title: String?
        var factsSnapshot: PsychologyCoachFacts?
    }

    struct MessageRow: Decodable, Sendable {
        var id: String?
        var role: String?
        var content: String?
        var promptKey: String?
        var prompt_key: String?
        var createdAt: String?
        var created_at: String?
        var attachments: [AttachmentRow]?

        struct AttachmentRow: Decodable, Sendable {
            var kind: String?
            var url: String?
            var storagePath: String?
            var storage_path: String?
            var tradeId: String?
            var trade_id: String?
        }
    }

    var conversation: Conversation?
    var messages: [MessageRow]?
}

nonisolated enum AIConversationMessagesBFFDecoding: Sendable {
    nonisolated static func promptKey(
        _ row: ConversationMessagesBFFResponse.MessageRow
    ) -> String? {
        row.promptKey ?? row.prompt_key
    }

    nonisolated static func createdAt(
        _ row: ConversationMessagesBFFResponse.MessageRow
    ) -> String? {
        row.createdAt ?? row.created_at
    }

    nonisolated static func factsSnapshot(
        _ conversation: ConversationMessagesBFFResponse.Conversation
    ) -> PsychologyCoachFacts? {
        conversation.factsSnapshot
    }

    nonisolated static func attachments(
        _ row: ConversationMessagesBFFResponse.MessageRow
    ) -> [TradeAIAttachment] {
        (row.attachments ?? []).compactMap { attachment in
            tradeAIAttachment(from: attachment)
        }
    }

    nonisolated static func tradeAIAttachment(
        from row: ConversationMessagesBFFResponse.MessageRow.AttachmentRow
    ) -> TradeAIAttachment? {
        let kind = row.kind ?? "uploaded_image"
        if kind == "trade" {
            let raw = row.tradeId ?? row.trade_id
            guard let raw, !raw.isEmpty else { return nil }
            return TradeAIAttachment(kind: "trade", tradeID: TradeID(raw))
        }
        if kind == "screenshot" || kind == "uploaded_image" {
            let url = row.url ?? ""
            let path = row.storagePath ?? row.storage_path
            if url.isEmpty, path == nil { return nil }
            return TradeAIAttachment(
                kind: kind,
                url: url,
                storagePath: path
            )
        }
        return nil
    }
}

private nonisolated struct ConversationInboxBFFResponse: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        var id: String?
        var kind: String?
        var trade_id: String?
        var title: String?
        var last_message_preview: String?
        var last_message_at: String?
    }

    var conversations: [Row]?
}