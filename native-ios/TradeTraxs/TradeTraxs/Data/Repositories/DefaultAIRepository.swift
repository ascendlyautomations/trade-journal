import Foundation

/// Production ``AIRepository`` — BFF `/api/analyze-trade` + `trade_ai_messages` persistence.
nonisolated struct DefaultAIRepository: AIRepository {
    private let supabase: SupabaseInfrastructure
    private let session: any SessionProviding

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
            requiresAuthentication: true
        )
        TradeAITrace.analysisResponse(status: response.statusCode, byteCount: response.data.count)

        let decoded = try? JSONDecoder().decode(AnalyzeTradeBFFResponse.self, from: response.data)
        let reply = decoded?.reply?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? decoded?.result?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch response.statusCode {
        case 200 ... 299:
            guard let reply, !reply.isEmpty else {
                throw AppError.unknown(message: "No response generated")
            }
            TradeAITrace.analysisDecoded()
            return TradeAIAnalyzeResponse(reply: AIGeneratedTextNormalizer.normalize(reply))
        case 401:
            throw AppError.domain(.permission(.notAuthenticated))
        case 403:
            return TradeAIAnalyzeResponse(
                reply: AIGeneratedTextNormalizer.normalize(
                    ProEntitlementResponseSanitizer.message(
                        statusCode: 403,
                        error: decoded?.error,
                        reply: reply
                    )
                )
            )
        case 429:
            throw AppError.unknown(message: decoded?.error ?? "Slow down — try again in a moment.")
        default:
            throw AppError.unknown(
                message: decoded?.error
                    ?? decoded?.reply
                    ?? "We couldn't complete the analysis. Please try again."
            )
        }
    }

    func loadConversation(tradeID: TradeID) async throws -> [TradeAIMessage] {
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
            }
        )
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/psychology-coach",
            method: .post,
            body: data,
            requiresAuthentication: true
        )

        let decoded = try? JSONDecoder().decode(PsychologyCoachBFFResponse.self, from: response.data)
        let reply = decoded?.reply?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch response.statusCode {
        case 200 ... 299:
            guard let reply, !reply.isEmpty else {
                throw AppError.unknown(message: "No response generated")
            }
            return PsychologyCoachAIResponse(reply: AIGeneratedTextNormalizer.normalize(reply))
        case 401:
            throw AppError.domain(.permission(.notAuthenticated))
        case 403:
            throw AppError.unknown(
                message: ProEntitlementResponseSanitizer.message(
                    statusCode: 403,
                    error: decoded?.error,
                    reply: reply
                )
            )
        case 429:
            throw AppError.unknown(message: decoded?.error ?? "Slow down — try again in a moment.")
        default:
            throw AppError.unknown(
                message: ProEntitlementResponseSanitizer.sanitizedOrNeutral(
                    decoded?.error ?? "Psychology coach unavailable. Your analytics still work offline."
                )
            )
        }
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
            throw AppError.unknown(message: decoded?.error ?? "Slow down — try again in a moment.")
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

    private func ensureThirdPartyAIConsent() async throws {
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

private nonisolated struct AnalyzeTradeBFFResponse: Decodable {
    var reply: String?
    var result: String?
    var error: String?
}

private nonisolated struct PsychologyCoachBFFBody: Encodable {
    var facts: PsychologyCoachFacts
    var mode: String
    var messages: [PsychologyCoachBFFMessage]
}

private nonisolated struct PsychologyCoachBFFMessage: Encodable {
    var role: String
    var content: String
}

private nonisolated struct PsychologyCoachBFFResponse: Decodable {
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

