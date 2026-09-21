import Foundation

#if DEBUG
enum DashboardAnalyticsV3PayloadProbe {
    struct Breakdown: Sendable {
        var totalBytes: Int
        var accountsBytes: Int
        var summaryBytes: Int
        var accountSummaryBytes: Int
        var dailyBytes: Int
        var equityBytes: Int
        var distributionBytes: Int
        var insightsBytes: Int
        var otherBytes: Int
        var summaryCount: Int
        var accountSummaryCount: Int
        var dailyRows: Int
    }

    static func measure(_ bootstrap: AnalyticsDashboardBootstrapV3) -> Breakdown {
        let encoder = JSONEncoder()
        func bytes<T: Encodable>(_ value: T) -> Int {
            (try? encoder.encode(value))?.count ?? 0
        }

        let data = bootstrap.data
        let presetsBytes = bytes(data.aggregatePresets)
        let accountMetricsBytes = bytes(data.account_preset_metrics ?? [])
        let accountsBytes = bytes(data.accounts)
        let metaBytes = bytes(bootstrap.meta)

        var equityBytes = 0
        var distributionBytes = 0
        var insightsBytes = 0
        for (_, bundle) in data.aggregatePresets {
            equityBytes += bytes(bundle.equity)
            distributionBytes += bytes(bundle.distributions)
            insightsBytes += bytes(bundle.insights)
        }

        let total = bytes(bootstrap)
        let known = presetsBytes + accountMetricsBytes + accountsBytes + metaBytes
        let other = max(0, total - known)

        return Breakdown(
            totalBytes: total,
            accountsBytes: accountsBytes,
            summaryBytes: presetsBytes,
            accountSummaryBytes: accountMetricsBytes,
            dailyBytes: 0,
            equityBytes: equityBytes,
            distributionBytes: distributionBytes,
            insightsBytes: insightsBytes,
            otherBytes: other,
            summaryCount: data.aggregatePresets.count,
            accountSummaryCount: data.account_preset_metrics?.count ?? 0,
            dailyRows: 0
        )
    }

    static func log(_ breakdown: Breakdown) {
        print(
            """
            [DashboardV3Payload] totalBytes=\(breakdown.totalBytes) accountsBytes=\(breakdown.accountsBytes) \
            summaryBytes=\(breakdown.summaryBytes) accountSummaryBytes=\(breakdown.accountSummaryBytes) \
            dailyBytes=\(breakdown.dailyBytes) equityBytes=\(breakdown.equityBytes) \
            distributionBytes=\(breakdown.distributionBytes) insightsBytes=\(breakdown.insightsBytes) \
            otherBytes=\(breakdown.otherBytes)
            """
        )
    }
}
#else
enum DashboardAnalyticsV3PayloadProbe {
    struct Breakdown: Sendable {
        var totalBytes: Int = 0
        var summaryCount: Int = 0
        var accountSummaryCount: Int = 0
        var dailyRows: Int = 0
    }

    static func measure(_ bootstrap: AnalyticsDashboardBootstrapV3) -> Breakdown { Breakdown() }
    static func log(_ breakdown: Breakdown) {}
}
#endif
