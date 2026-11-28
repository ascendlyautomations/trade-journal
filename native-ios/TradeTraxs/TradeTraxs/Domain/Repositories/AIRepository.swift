import Foundation

/// Trade AI, BFF analysis + server conversation persistence.
nonisolated protocol AIRepository: Sendable {
    /// Legacy web-shaped analyze (still used by fallbacks / tests).
    func analyzeTrade(_ request: TradeAIAnalyzeRequest) async throws -> TradeAIAnalyzeResponse

    /// Authoritative trade turn: analyze + persist on server (`/api/ai/trade-turn`).
    func analyzeTradeTurn(_ request: TradeAITradeTurnRequest) async throws -> TradeAITurnResponse

    /// General portfolio turn (`/api/ai/portfolio-turn`).
    func analyzePortfolioTurn(_ request: TradeAIPortfolioTurnRequest) async throws -> TradeAITurnResponse

    /// Idempotent retry save without re-running OpenAI (`/api/ai/persist-turn`).
    func persistTurn(_ request: TradeAIPersistTurnRequest) async throws

    /// Owner-only private bucket upload for Trade AI message attachments.
    func uploadAICoachAttachment(_ request: TradeAIUploadAttachmentRequest) async throws -> TradeAIAttachment

    /// Create a new general Trade AI thread with frozen scope (`/api/ai/conversations/create`).
    func createGeneralTradeConversation(
        _ request: TradeAICreateConversationRequest
    ) async throws -> TradeAICreateConversationResponse

    /// Loads persisted conversation turns for a trade (legacy `trade_ai_messages` or `ai_messages`).
    func loadConversation(tradeID: TradeID) async throws -> [TradeAIMessage]

  /// Loads messages for a shared conversation id (`/api/ai/conversations/:id/messages`).
    func loadConversationMessages(conversationID: AIConversationID) async throws -> (TradeAIConversationMeta, [TradeAIMessage])

    /// Inbox rows for Messages Trade AI section.
    func loadConversationInbox(limit: Int) async throws -> [TradeAIConversationInboxItem]

    /// Updates conversation title (`PATCH /api/ai/conversations/:id`).
    func renameAICoachConversation(id: AIConversationID, title: String) async throws

    /// Legacy direct PostgREST insert (deprecated — server persist preferred).
    func persistMessages(_ messages: [TradeAIMessage], tradeID: TradeID) async throws

    /// Posts structured psychology facts to `/api/psychology-coach`, AI explains, never calculates stats.
    func explainPsychologyCoach(_ request: PsychologyCoachAIRequest) async throws -> PsychologyCoachAIResponse

    /// Account-wide trade coaching, `/api/general-trade-coach`.
    func analyzeGeneralTrading(_ request: GeneralTradeAIRequest) async throws -> GeneralTradeAIResponse

    /// Phase 3, multimodal screenshot extraction via authenticated BFF fallback.
    func extractScreenshotTrades(_ request: ScreenshotAIExtractRequest) async throws -> ScreenshotAIExtractResponse
}
