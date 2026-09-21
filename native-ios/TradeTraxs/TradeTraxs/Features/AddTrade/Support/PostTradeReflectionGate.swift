import Foundation
import Observation

@MainActor
@Observable
final class PostTradeReflectionGate {
    static let shared = PostTradeReflectionGate()

    private(set) var pendingTrade: Trade?

    private init() {}

    func present(_ trade: Trade) {
        pendingTrade = trade
    }

    func clear() {
        pendingTrade = nil
    }

    func saveReflection(
        exitEmotion: String?,
        executionRating: Int?,
        trades: any TradeRepository,
        detailCache: DetailPresentationCache
    ) async -> String? {
        guard let trade = pendingTrade else {
            clear()
            return nil
        }
        guard exitEmotion != nil || executionRating != nil else {
            clear()
            return nil
        }

        let draft = TradeDraft(
            accountID: trade.accountID,
            symbol: trade.symbol,
            side: trade.side,
            mode: trade.mode,
            quantity: trade.quantity,
            entryPrice: trade.entryPrice,
            exitPrice: trade.exitPrice,
            entryAt: trade.entryAt,
            exitAt: trade.exitAt,
            realizedPnL: trade.realizedPnL,
            riskReward: trade.riskReward,
            points: trade.points,
            sessionLabel: trade.sessionLabel,
            strategy: trade.strategy,
            visibility: trade.visibility,
            publicCaption: trade.publicCaption,
            noteBody: trade.notes,
            timeframe: trade.timeframe,
            newsEvent: trade.newsEvent ?? false,
            confidence: trade.confidence,
            emotion: trade.emotion,
            followedPlan: trade.followedPlan ?? false,
            marketCondition: trade.marketCondition,
            psychologyNotes: trade.psychologyNotes,
            exitEmotion: exitEmotion,
            executionRating: executionRating,
            imageDisplayMode: trade.imageDisplayMode,
            durationSeconds: trade.durationSeconds,
            durationText: trade.durationText,
            imageURL: trade.thumbnail?.id
        )

        do {
            let updated = try await trades.update(id: trade.id, draft: draft, previous: trade)
            detailCache.seed(updated)
            TradeJournalMutationStore.shared.noteUpdated(updated, previous: trade)
            clear()
            return nil
        } catch {
            clear()
            return "Reflection didn't save. Your trade was still recorded."
        }
    }
}
