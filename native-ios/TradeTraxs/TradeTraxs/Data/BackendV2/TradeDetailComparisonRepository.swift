import Foundation

nonisolated struct TradeDetailOwnerComparisonBootstrapV1: Codable, Sendable, Equatable {
    var meta: BootstrapMetaV1
    var data: DataPayload

    nonisolated struct DataPayload: Codable, Sendable, Equatable {
        var cohort: CohortWire?
        var cohorts: CohortBundleWire?
        var ticker_history: TickerHistoryWire?
    }

    nonisolated struct CohortBundleWire: Codable, Sendable, Equatable {
        var all: CohortWire?
        var account_mode: CohortWire?
        var setup: CohortWire?
        var session: CohortWire?
    }

    nonisolated struct CohortWire: Codable, Sendable, Equatable {
        var trade_count: Int
        var avg_pnl: Double?
        var win_rate: Double?
        var avg_rr: Double?
        var avg_target_rr: Double?
        var avg_realized_rr: Double?
        var avg_hold_seconds: Double?
        var pnl_percentile: Double?
        var rr_percentile: Double?
        var target_rr_percentile: Double?
        var realized_rr_percentile: Double?
        var hold_shorter_than_percent: Double?
        var long: SideSliceWire?
        var short: SideSliceWire?
    }

    nonisolated struct SideSliceWire: Codable, Sendable, Equatable {
        var trade_count: Int
        var win_rate: Double?
        var avg_pnl: Double?
        var total_pnl: Double?
    }

    nonisolated struct TickerHistoryWire: Codable, Sendable, Equatable {
        var ticker: String
        var previous_trade_count: Int
        var win_rate: Double?
        var total_pnl: Double?
        var profit_factor: Double?
        var avg_trade_pnl: Double?
        var better_than_count: Int
        var recent_wins: Int
        var recent_trade_count: Int
        var long: SideSliceWire?
        var short: SideSliceWire?
        var sessions: [SessionSliceWire]?
        var window_30d: TickerWindowWire?
        var window_90d: TickerWindowWire?
    }

    nonisolated struct SessionSliceWire: Codable, Sendable, Equatable {
        var session: String
        var trade_count: Int
        var win_rate: Double?
        var avg_pnl: Double?
    }

    nonisolated struct TickerWindowWire: Codable, Sendable, Equatable {
        var trade_count: Int
        var win_rate: Double?
        var total_pnl: Double?
        var avg_pnl: Double?
        var profit_factor: Double?
    }

    func validateContractVersion() throws {
        try BackendV2Versioning.assertContractVersion(meta.contract_version)
    }
}

enum TradeDetailComparisonLoader {
    enum LoaderError: Error, Sendable {
        case rpcUnavailable
    }

    @MainActor
    static func load(
        trade: Trade,
        rpc: any RPCClient
    ) async throws -> TradeDetailAnalytics.Result {
        let bootstrap = try await loadBootstrap(trade: trade, rpc: rpc)
        return TradeDetailAnalytics.map(from: bootstrap.data, trade: trade)
    }

    @MainActor
    static func loadBootstrap(
        trade: Trade,
        rpc: any RPCClient
    ) async throws -> TradeDetailOwnerComparisonBootstrapV1 {
        let client = BackendV2RPCClient(transport: rpc)
        let args = TradeDetailComparisonRpcArguments(tradeID: trade.id.rawValue)
        let body = try JSONEncoder().encode(args)
        let bootstrap = try await client.call(
            .tradeDetailOwnerComparison,
            argumentsJSON: body,
            as: TradeDetailOwnerComparisonBootstrapV1.self,
            options: BackendV2RPCCallOptions(cacheMiss: true)
        )
        try bootstrap.validateContractVersion()
        return bootstrap
    }
}

private struct TradeDetailComparisonRpcArguments: Encodable, Sendable {
    var p_trade_id: String

    init(tradeID: String) {
        p_trade_id = tradeID
    }
}