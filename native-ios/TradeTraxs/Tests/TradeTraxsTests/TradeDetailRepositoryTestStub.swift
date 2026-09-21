import Foundation
@testable import TradeTraxs

nonisolated struct NullTradeDetailRepository: TradeDetailRepository {
    func cachedDetail(tradeID: TradeID) async -> TradeDetail? { nil }

    func load(tradeID: TradeID, policy: TradeDetailLoadPolicy) async throws -> TradeDetail {
        throw AppError.unknown(message: "TradeDetailRepository test stub")
    }

    func replaceCachedDetail(_ detail: TradeDetail, authority: TradeDetailAuthority) async {}

    func evict(tradeID: TradeID) async {}

    func resetSessionCache() async {}
}
