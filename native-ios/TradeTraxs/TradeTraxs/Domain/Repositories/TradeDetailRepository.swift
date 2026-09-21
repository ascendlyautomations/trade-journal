import Foundation

nonisolated struct TradeDetailLoadPolicy: Sendable, Equatable {
    var forceNetwork: Bool

    static let `default` = TradeDetailLoadPolicy(forceNetwork: false)
}

nonisolated protocol TradeDetailRepository: Sendable {
    func cachedDetail(tradeID: TradeID) async -> TradeDetail?
    func load(
        tradeID: TradeID,
        policy: TradeDetailLoadPolicy
    ) async throws -> TradeDetail
    func replaceCachedDetail(_ detail: TradeDetail, authority: TradeDetailAuthority) async
    func evict(tradeID: TradeID) async
    func resetSessionCache() async
}
