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

    static func shouldOfferQuickReflection(for trade: Trade) -> Bool {
        !TradeReviewCatalog.quickReflectionIsRedundant(for: trade)
    }

    func saveReflection(
        patch: PostTradePsychologySavePatch,
        trades: any TradeRepository,
        detailCache: DetailPresentationCache
    ) async -> String? {
        guard let trade = pendingTrade else {
            clear()
            return nil
        }

        guard patch.hasAnyValue else {
            clear()
            return nil
        }

        var draft = Self.tradeDraft(from: trade)
        TradeReviewCatalog.applyPsychologyPatch(patch, to: &draft)

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

    private static func tradeDraft(from trade: Trade) -> TradeDraft {
        TradeDraft(
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
            dollarRisk: trade.dollarRisk,
            maxRrReached: trade.maxRrReached,
            realizedRr: trade.realizedRr,
            fullTakeProfit: trade.fullTakeProfit,
            earlyExit: trade.earlyExit,
            exitRr: trade.exitRr,
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
            followedPlan: trade.followedPlan,
            marketCondition: trade.marketCondition,
            psychologyNotes: trade.psychologyNotes,
            exitEmotion: trade.exitEmotion,
            executionRating: trade.executionRating,
            imageDisplayMode: trade.imageDisplayMode,
            durationSeconds: trade.durationSeconds,
            durationText: trade.durationText,
            imageURL: trade.thumbnail?.id
        )
    }
}