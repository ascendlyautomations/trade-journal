import Foundation

nonisolated protocol SaveTradeUseCase: Sendable {
    func execute(_ draft: TradeDraft) async throws -> Trade
}

nonisolated protocol UpdateTradeUseCase: Sendable {
    func execute(_ trade: Trade) async throws -> Trade
}

nonisolated protocol DeleteTradeUseCase: Sendable {
    func execute(id: TradeID) async throws
}

nonisolated protocol ImportTradesUseCase: Sendable {
    func execute(accountID: TradingAccountID, fileData: Data, fileName: String) async throws -> TradeImportResult
}

nonisolated struct TradeImportResult: Hashable, Sendable {
    var importedCount: Int
    var failedCount: Int
    var tradeIDs: [TradeID]
}
