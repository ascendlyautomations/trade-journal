import Foundation

/// Reconstruct Dashboard V3 bootstrap from GRDB snapshot + session/disk envelope.
nonisolated enum DashboardAnalyticsGRDBMapper {
    static func bootstrap(
        snapshot: AnalyticsLocalDashboardV3Snapshot,
        viewerID: ProfileID,
        diskEnvelope: AnalyticsDashboardBootstrapV3?,
        sessionAccounts: [TradingAccount]
    ) -> AnalyticsDashboardBootstrapV3 {
        let meta = diskEnvelope?.meta ?? BootstrapMetaV1(
            contract_version: BackendV2Versioning.contractVersion,
            server_time: ISO8601DateFormatter().string(from: Date()),
            viewer_id: viewerID.rawValue
        )
        let accountWires: [DashboardAccountWireV1] = {
            if let disk = diskEnvelope?.data.accounts, !disk.isEmpty { return disk }
            return sessionAccounts.map { $0.asDashboardWireV1() }
        }()
        let payout = diskEnvelope?.data.payout_total
        return AnalyticsDashboardBootstrapV3(
            meta: meta,
            data: AnalyticsDashboardBootstrapV3.DataPayload(
                revision: PostgresFlexibleDouble(Double(snapshot.revision)),
                as_of_et: snapshot.asOfET,
                payload_kind: diskEnvelope?.data.payload_kind,
                payout_total: payout,
                accounts: accountWires,
                presets: snapshot.aggregatePresets.mapValues { AnalyticsDashboardAggregatePresetV1(full: $0) },
                account_preset_metrics: snapshot.accountPresetMetrics,
                scopes: nil
            )
        )
    }
}
