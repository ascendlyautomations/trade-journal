import Foundation

/// Production ``AIRepository``, BFF `/api/analyze-trade` + `trade_ai_messages` persistence.
nonisolated struct DefaultAIRepository: AIRepository {
    let supabase: SupabaseInfrastructure
    let session: any SessionProviding

    private static let table = "trade_ai_messages"
    private static let selectColumns = "id,trade_id,user_id,role,content,prompt_key,created_at"

    init(supabase: SupabaseInfrastructure, session: any SessionProviding) {
        self.supabase = supabase
        self.session = session
    }

    func analyzeTrade(_ request: TradeAIAnalyzeRequest) async throws -> TradeAIAnalyzeResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        TradeAITrace.analysisStarted()
        let body = AnalyzeTradeBFFBody(
            trade: request.context.tradePayload,
            messages: request.messages.map {
                AnalyzeTradeBFFMessage(role: $0.role.rawValue, content: $0.content)
            }
        )
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/analyze-trade",
            method: .post,
            body: data,
            requiresAuthentication: true,
            acceptsNonSuccessStatusCodes: true
        )
        TradeAITrace.analysisResponse(status: response.statusCode, byteCount: response.data.count)
        return TradeAIAnalyzeHTTPMapping.map(statusCode: response.statusCode, data: response.data)
    }

    func loadConversation(tradeID: TradeID) async throws -> [TradeAIMessage] {
        if let transport = supabase.transport {
            let response = try await transport.send(
                host: .bff,
                path: "/api/ai/conversations/trade/\(tradeID.rawValue)/messages",
                method: .get,
                requiresAuthentication: true,
                acceptsNonSuccessStatusCodes: true
            )
            if (200 ... 299).contains(response.statusCode) {
                let decoded = try? JSONDecoder().decode(ConversationMessagesBFFResponse.self, from: response.data)
                let mapped = (decoded?.messages ?? []).compactMap { row -> TradeAIMessage? in
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
                #if DEBUG
                TradeAITrace.conversationHistoryLoaded(
                    tradeScoped: true,
                    status: response.statusCode,
                    byteCount: response.data.count,
                    decoded: decoded != nil,
                    messageCount: mapped.count
                )
                #endif
                return mapped
            }
        }

        guard let userID = await session.currentUserID else { return [] }
        do {
            let rows: [TradeAIMessageDTO] = try await supabase.database.select(
                TradeAIMessageDTO.self,
                from: Self.table,
                query: [
                    SupabaseQuery.select(Self.selectColumns),
                    SupabaseQuery.eq("trade_id", tradeID.rawValue),
                    SupabaseQuery.eq("user_id", userID.rawValue),
                    URLQueryItem(name: "order", value: "created_at.asc"),
                ]
            )
            return rows.compactMap { $0.toDomain() }
        } catch {
            if Self.isMissingTableError(error) { return [] }
            throw error
        }
    }

    func persistMessages(_ messages: [TradeAIMessage], tradeID: TradeID) async throws {
        guard !messages.isEmpty else { return }
        guard let userID = await session.currentUserID else { return }

        let rows = TradeAIMessagePersistence.makeInsertRows(
            messages: messages,
            tradeID: tradeID,
            userID: userID
        )
        TradeAITrace.persistenceStarted(rowCount: rows.count, payloadType: "TradeAIMessageInsertRow[]")

        let payload: Data
        do {
            payload = try TradeAIMessagePersistence.encodeInsertPayload(rows)
        } catch {
            TradeAITrace.persistenceFailed(error: error)
            throw AppError.unknown(message: "Could not prepare analysis save.")
        }

        do {
            try await supabase.database.insertJSON(payload, into: Self.table)
            TradeAITrace.persistenceCompleted(rowCount: rows.count)
        } catch {
            if Self.isMissingTableError(error) { return }
            if let domain = Self.traxProFeatureError(from: error) {
                TradeAITrace.persistenceFailed(error: error)
                throw domain
            }
            TradeAITrace.persistenceFailed(error: error)
            throw error
        }
    }

    func explainPsychologyCoach(_ request: PsychologyCoachAIRequest) async throws -> PsychologyCoachAIResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let body = PsychologyCoachBFFBody(
            facts: request.facts,
            mode: request.mode.rawValue,
            messages: request.messages.map {
                PsychologyCoachBFFMessage(role: $0.role, content: $0.content)
            },
            conversationId: request.conversationID?.rawValue,
            createConversation: request.createConversation,
            assistantMessageId: request.assistantMessageID,
            userMessage: request.userMessage.map {
                PsychologyCoachBFFUserMessage(
                    id: $0.id,
                    displayContent: $0.displayContent,
                    createdAt: $0.createdAt
                )
            },
            persistCachedOnly: request.persistCachedOnly,
            cachedReply: request.cachedReply
        )
        let data = try transport.encodeJSON(body)
        #if DEBUG
        PsychologyCoachTrace.requestStarted(
            mode: request.mode.rawValue,
            persistCachedOnly: request.persistCachedOnly,
            bodyBytes: data.count,
            hasConversationID: request.conversationID != nil
        )
        #endif
        let response = try await transport.send(
            host: .bff,
            path: "/api/psychology-coach",
            method: .post,
            body: data,
            requiresAuthentication: true,
            acceptsNonSuccessStatusCodes: true
        )
        #if DEBUG
        let contentType = (response.headers["Content-Type"] as? String)
            ?? (response.headers["content-type"] as? String)
        PsychologyCoachTrace.responseReceived(
            status: response.statusCode,
            byteCount: response.data.count,
            contentType: contentType
        )
        #endif
        return try PsychologyCoachHTTPMapping.map(statusCode: response.statusCode, data: response.data)
    }

    func analyzeGeneralTrading(_ request: GeneralTradeAIRequest) async throws -> GeneralTradeAIResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }
        let body = GeneralTradeCoachBFFBody(
            question: request.question,
            messages: request.messages.map { GeneralTradeCoachBFFMessage(role: $0.role, content: $0.content) }
        )
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/general-trade-coach",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        let decoded = try? JSONDecoder().decode(GeneralTradeCoachBFFResponse.self, from: response.data)
        let reply = decoded?.reply?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.statusCode == 200, let reply, !reply.isEmpty else {
            throw AppError.unknown(message: decoded?.error ?? "Trade AI is unavailable.")
        }
        return GeneralTradeAIResponse(reply: AIGeneratedTextNormalizer.normalize(reply))
    }

    func extractScreenshotTrades(_ request: ScreenshotAIExtractRequest) async throws -> ScreenshotAIExtractResponse {
        try await ensureThirdPartyAIConsent()
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }

        let data = try transport.encodeJSON(request)
        let response = try await transport.send(
            host: .bff,
            path: "/api/trade-import/screenshot-extract",
            method: .post,
            body: data,
            requiresAuthentication: true
        )

        let decoded = try? JSONDecoder().decode(ScreenshotAIExtractResponse.self, from: response.data)

        switch response.statusCode {
        case 200 ... 299:
            guard let extraction = decoded?.extraction else {
                throw AppError.unknown(message: decoded?.error ?? "No extraction result")
            }
            return ScreenshotAIExtractResponse(extraction: extraction, error: nil)
        case 401:
            throw AppError.domain(.permission(.notAuthenticated))
        case 403:
            throw AppError.unknown(
                message: ProEntitlementResponseSanitizer.message(
                    statusCode: 403,
                    error: decoded?.error
                )
            )
        case 429:
            throw AppError.unknown(message: decoded?.error ?? "Slow down, try again in a moment.")
        case 400:
            throw AppError.unknown(message: decoded?.error ?? "Unsupported screenshot")
        default:
            throw AppError.unknown(
                message: ProEntitlementResponseSanitizer.sanitizedOrNeutral(
                    decoded?.error ?? "Screenshot extraction failed. Please try again."
                )
            )
        }
    }

    func ensureThirdPartyAIConsent() async throws {
        let allowed = await ThirdPartyAIConsentGate.ensureConsent(session: session)
        guard allowed else {
            throw ThirdPartyAIConsentError.userDeclined
        }
    }

    private static func isMissingTableError(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("trade_ai_messages")
            || text.contains("pgrst205")
            || text.contains("schema cache")
            || text.contains("does not exist")
            || text.contains("404")
    }

    private static func traxProFeatureError(from error: Error) -> AppError? {
        let text = String(describing: error)
        if text.localizedCaseInsensitiveContains("TRAXPRO_AI_ANALYST_REQUIRED") {
            return .unknown(message: "TRAXPRO_AI_ANALYST_REQUIRED")
        }
        return nil
    }
}

// MARK: - BFF DTOs (Data-layer only)

private nonisolated struct AnalyzeTradeBFFBody: Encodable {
    var trade: TradeAITradePayload
    var messages: [AnalyzeTradeBFFMessage]
}

private nonisolated struct AnalyzeTradeBFFMessage: Encodable {
    var role: String
    var content: String
}

private nonisolated struct PsychologyCoachBFFBody: Encodable {
    var facts: PsychologyCoachFacts
    var mode: String
    var messages: [PsychologyCoachBFFMessage]
    var conversationId: String?
    var createConversation: Bool
    var assistantMessageId: String?
    var userMessage: PsychologyCoachBFFUserMessage?
    var persistCachedOnly: Bool
    var cachedReply: String?
}

private nonisolated struct PsychologyCoachBFFUserMessage: Encodable {
    var id: String
    var displayContent: String
    var createdAt: String?
}

private nonisolated struct PsychologyCoachBFFMessage: Encodable {
    var role: String
    var content: String
}

private nonisolated struct GeneralTradeCoachBFFBody: Encodable {
    var question: String
    var messages: [GeneralTradeCoachBFFMessage]
}

private nonisolated struct GeneralTradeCoachBFFMessage: Encodable {
    var role: String
    var content: String
}

private nonisolated struct GeneralTradeCoachBFFResponse: Decodable {
    var reply: String?
    var error: String?
}

// MARK: - Persistence DTOs

private nonisolated struct TradeAIMessageDTO: Decodable {
    var id: String?
    var trade_id: String?
    var user_id: String?
    var role: String?
    var content: String?
    var prompt_key: String?
    var created_at: String?

    func toDomain() -> TradeAIMessage? {
        guard let roleRaw = role,
              let role = TradeAIMessageRole(rawValue: roleRaw),
              let content,
              !content.isEmpty
        else { return nil }
        return TradeAIMessage(
            id: id ?? UUID().uuidString,
            role: role,
            content: role == .assistant
                ? AIGeneratedTextNormalizer.normalize(content)
                : content,
            promptKey: prompt_key,
            createdAt: created_at.flatMap(ISO8601.date(from:)) ?? Date()
        )
    }
}

