import Foundation

/// Trade AI — BFF analysis + Supabase conversation persistence.
nonisolated protocol AIRepository: Sendable {
    /// Posts to `/api/analyze-trade` with the same body shape as the web analyst.
    func analyzeTrade(_ request: TradeAIAnalyzeRequest) async throws -> TradeAIAnalyzeResponse

    /// Loads persisted conversation turns for a trade (chronological). Never regenerates AI.
    func loadConversation(tradeID: TradeID) async throws -> [TradeAIMessage]

    /// Appends completed turns to Supabase. Soft-fails if persistence is unavailable.
    func persistMessages(_ messages: [TradeAIMessage], tradeID: TradeID) async throws

    /// Posts structured psychology facts to `/api/psychology-coach` — AI explains, never calculates stats.
    func explainPsychologyCoach(_ request: PsychologyCoachAIRequest) async throws -> PsychologyCoachAIResponse

    /// Phase 3 — multimodal screenshot extraction via authenticated BFF fallback.
    func extractScreenshotTrades(_ request: ScreenshotAIExtractRequest) async throws -> ScreenshotAIExtractResponse
}
