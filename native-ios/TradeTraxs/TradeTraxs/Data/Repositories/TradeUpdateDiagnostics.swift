import Foundation
import OSLog

#if DEBUG
/// DEBUG-only tracing for Edit Trade → PostgREST UPDATE → authoritative SELECT.
nonisolated enum TradeUpdateDiagnostics {
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "TradeUpdate"
    )

    static func logUpdateAttempt(tradeID: TradeID, body: TradeDTO.UpdateBody) {
        logger.debug(
            """
            trade.update.attempt id=\(tradeID.rawValue, privacy: .public) \
            columns=[ticker,direction,mode,contracts,entry_price,exit_price,entry_time,exit_time,trade_date,pnl,rr,points,session,strategy,notes,image_url,is_public,public_description,account_*] \
            rr=\(body.rr.map { String($0) } ?? "null", privacy: .public) \
            points=\(body.points.map { String($0) } ?? "null", privacy: .public) \
            pnl=\(body.pnl.map { String($0) } ?? "null", privacy: .public) \
            contracts=\(body.contracts, privacy: .public)
            """
        )
    }

    static func logUpdateResponse(tradeID: TradeID, statusCode: Int, bodyBytes: Int) {
        logger.debug(
            "trade.update.response id=\(tradeID.rawValue, privacy: .public) status=\(statusCode, privacy: .public) bytes=\(bodyBytes, privacy: .public)"
        )
    }

    static func logVerifyPersisted(tradeID: TradeID, draft: TradeDraft, persisted: Trade) {
        let submittedRR = draft.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue }
        let persistedRR = persisted.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue }
        let submittedPnL = draft.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue }
        let persistedPnL = persisted.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue }
        let submittedPoints = draft.points.map { NSDecimalNumber(decimal: $0).doubleValue }
        let persistedPoints = persisted.points.map { NSDecimalNumber(decimal: $0).doubleValue }

        logger.debug(
            """
            trade.update.verify id=\(tradeID.rawValue, privacy: .public) \
            rr submitted=\(submittedRR.map { String($0) } ?? "null", privacy: .public) \
            persisted=\(persistedRR.map { String($0) } ?? "null", privacy: .public) \
            pnl submitted=\(submittedPnL.map { String($0) } ?? "null", privacy: .public) \
            persisted=\(persistedPnL.map { String($0) } ?? "null", privacy: .public) \
            points submitted=\(submittedPoints.map { String($0) } ?? "null", privacy: .public) \
            persisted=\(persistedPoints.map { String($0) } ?? "null", privacy: .public)
            """
        )

        if !approximatelyEqual(submittedRR, persistedRR) {
            logger.error(
                "trade.update.verify MISMATCH rr id=\(tradeID.rawValue, privacy: .public) submitted=\(submittedRR.map { String($0) } ?? "null", privacy: .public) persisted=\(persistedRR.map { String($0) } ?? "null", privacy: .public)"
            )
        }
        if !approximatelyEqual(submittedPnL, persistedPnL) {
            logger.error(
                "trade.update.verify MISMATCH pnl id=\(tradeID.rawValue, privacy: .public)"
            )
        }
        if !approximatelyEqual(submittedPoints, persistedPoints) {
            logger.error(
                "trade.update.verify MISMATCH points id=\(tradeID.rawValue, privacy: .public)"
            )
        }
    }

    private static func approximatelyEqual(_ lhs: Double?, _ rhs: Double?, tolerance: Double = 0.0001) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return abs(l - r) <= tolerance
        default:
            return false
        }
    }
}
#endif
