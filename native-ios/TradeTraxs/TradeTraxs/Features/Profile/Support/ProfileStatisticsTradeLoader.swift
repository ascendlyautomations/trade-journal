import Foundation

/// Legacy fallback — cursor-paginates the full public trade history when `rpc_v1_profile_statistics_bootstrap` is unavailable.
enum ProfileStatisticsTradeLoader {
    static func loadPublicTradeInputs(
        profileID: ProfileID,
        trades: any TradeRepository,
        rpc: (any RPCClient)?,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) async throws -> [ProfileStatisticsMetrics.TradeInput] {
        var collected: [Trade] = []
        var seen = Set<TradeID>()

        if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
            var cursor: String?
            repeat {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .trades,
                    profileID: profileID,
                    rpc: rpc,
                    cursor: cursor
                )
                let page = applied.trades ?? []
                for trade in page where seen.insert(trade.id).inserted {
                    collected.append(trade)
                }
                cursor = applied.nextCursor
            } while cursor != nil
        } else {
            var cursor: String?
            repeat {
                let page = try await trades.trades(
                    ownedBy: profileID,
                    accountID: nil,
                    page: PageRequest(cursor: cursor, limit: ProfileTabBootstrapLoader.defaultPageSize),
                    publicOnly: true
                )
                for trade in page.items where seen.insert(trade.id).inserted {
                    collected.append(trade)
                }
                cursor = page.nextCursor
            } while cursor != nil
        }

        return collected.map {
            ProfileStatisticsMetrics.tradeInput(from: $0, accountModes: accountModes)
        }
    }
}
