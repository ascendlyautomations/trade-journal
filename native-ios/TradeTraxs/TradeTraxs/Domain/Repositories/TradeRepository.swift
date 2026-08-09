import Foundation

nonisolated protocol TradeRepository: Sendable {
    func trade(id: TradeID) async throws -> Trade
    /// - Parameter publicOnly: When `true`, mirrors web Profile (`is_public = true`).
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade>
    func save(_ draft: TradeDraft) async throws -> Trade
    func update(_ trade: Trade) async throws -> Trade
    func delete(id: TradeID) async throws
    func images(for tradeID: TradeID) async throws -> [TradeImage]
    func notes(for tradeID: TradeID) async throws -> [TradeNote]
    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount]
}
