import Foundation

nonisolated enum PropFirmBootstrapApplier {
    @MainActor
    static func apply(
        _ bootstrap: PropFirmBootstrapV1,
        accountID: TradingAccountID,
        profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) throws -> PropFirmBootstrapLoader.LoadResult {
        try bootstrap.validateContractVersion()

        let accounts = bootstrap.data.accounts.compactMap { row -> TradingAccount? in
            let dto = row.asAccountDTO(ownerID: profileID.rawValue)
            return try? TradingAccountMapper.mapToDomain(dto)
        }

        if !accounts.isEmpty {
            SessionAccountsStore.shared.seed(
                accounts,
                for: profileID,
                detailCache: detailCache,
                kind: .rest
            )
            detailCache.seed(trades: mapTrades(bootstrap.data.trades, ownerID: profileID))
        }

        guard let account = accounts.first(where: { $0.id == accountID }),
              account.isPropFirmAccount
        else {
            throw PropFirmBootstrapLoader.LoaderError.accountNotFound
        }

        let tradeList = mapTrades(bootstrap.data.trades, ownerID: profileID)
            .filter { $0.accountID == accountID }

        guard let snapshot = PropFirmStatusSnapshot.build(account: account, trades: tradeList) else {
            throw PropFirmBootstrapLoader.LoaderError.accountNotFound
        }

        return PropFirmBootstrapLoader.LoadResult(
            snapshot: snapshot,
            seededTradeCount: tradeList.count
        )
    }

    private static func mapTrades(
        _ rows: [PropFirmTradeWireV1],
        ownerID: ProfileID
    ) -> [Trade] {
        rows.compactMap { row in
            let dto = row.asTradeDTO(ownerID: ownerID.rawValue)
            return try? TradeMapper.mapToDomain(dto)
        }
    }
}
