import Foundation

/// Calendar day RPC slim trade rows → ``TradeSummary`` (wire unchanged).
nonisolated enum TradeSummaryCalendarMapper {
    static func mapDayTrades(
        _ rows: [DashboardTradeWireV1],
        ownerID: ProfileID
    ) -> [TradeSummary] {
        var summaries: [TradeSummary] = []
        summaries.reserveCapacity(rows.count)
        for row in rows {
            let dto = row.asTradeDTO(ownerID: ownerID.rawValue)
            guard let trade = try? TradeMapper.mapToDomain(dto) else { continue }
            summaries.append(TradeSummaryMapper.summary(fromPartialListTrade: trade))
        }
        return summaries
    }
}
