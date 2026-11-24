import Foundation

/// Owner journal trade sharing — web URL + optional make-public before external link share.
enum JournalTradeShareSupport {
    struct Presentation: Identifiable, Equatable {
        var id: TradeID { ownerAccess.tradeID }
        var target: SharedContentShareTarget
        var ownerAccess: TradeOwnerShareAccess
    }

    static func presentation(for summary: TradeSummary) -> Presentation {
        let target = shareTarget(for: summary)
        return Presentation(
            target: target,
            ownerAccess: TradeOwnerShareAccess(
                tradeID: summary.id,
                ownerProfileID: summary.ownerProfileID,
                visibility: summary.visibility
            )
        )
    }

    static func presentation(for trade: Trade) -> Presentation {
        let target = shareTarget(for: trade)
        return Presentation(
            target: target,
            ownerAccess: TradeOwnerShareAccess(
                tradeID: trade.id,
                ownerProfileID: trade.ownerProfileID,
                visibility: trade.visibility
            )
        )
    }

    static func shareTarget(for summary: TradeSummary) -> SharedContentShareTarget {
        shareTarget(
            tradeID: summary.id,
            ownerProfileID: summary.ownerProfileID,
            symbol: summary.symbol.ticker,
            side: summary.side,
            realizedPnL: summary.realizedPnL
        )
    }

    static func shareTarget(for trade: Trade) -> SharedContentShareTarget {
        shareTarget(
            tradeID: trade.id,
            ownerProfileID: trade.ownerProfileID,
            symbol: trade.symbol.ticker,
            side: trade.side,
            realizedPnL: trade.realizedPnL
        )
    }

    private static func shareTarget(
        tradeID: TradeID,
        ownerProfileID: ProfileID,
        symbol: String,
        side: TradeSide,
        realizedPnL: Money?
    ) -> SharedContentShareTarget {
        let sideLabel = side == .long ? "Long" : "Short"
        let pnl = TradeDisplay.pnlText(realizedPnL)
        return SharedContentShareTarget(
            reference: .trade(tradeID),
            contentLink: .trade(tradeID),
            shareTitle: "Share Trade",
            externalShareText: "\(symbol) \(sideLabel) \(pnl) on TradeTraxs",
            roomTradeID: tradeID
        )
    }

    static func tradeDraft(from trade: Trade, visibility: ContentVisibility) -> TradeDraft {
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
            visibility: visibility,
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

    /// Web-style `is_public` toggle for link sharing — uses full ``TradeRepository/update(id:draft:previous:)``.
    @MainActor
    static func makePublicForSharing(
        trade: Trade,
        trades: any TradeRepository,
        session: any SessionProviding
    ) async throws -> Trade {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let owner = ProfileID(userID.rawValue)
        guard trade.ownerProfileID == owner else {
            throw AppError.domain(.permission(.notOwner))
        }
        guard trade.visibility != .public else { return trade }
        let draft = tradeDraft(from: trade, visibility: .public)
        let updated = try await trades.update(id: trade.id, draft: draft, previous: trade)
        TradeJournalMutationStore.shared.noteUpdated(updated, previous: trade)
        return updated
    }
}

/// Private journal trades need owner confirmation before link-based sharing.
struct TradeOwnerShareAccess: Equatable, Sendable {
    var tradeID: TradeID
    var ownerProfileID: ProfileID
    var visibility: ContentVisibility
}