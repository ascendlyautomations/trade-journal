import Foundation

#if DEBUG
nonisolated enum AnalyticsGRDBProbe {
    static func logOpen(elapsedMs: Int) {
        print("[AnalyticsGRDB] open elapsedMs=\(elapsedMs)")
    }

    static func logMigration(elapsedMs: Int) {
        print("[AnalyticsGRDB] migration elapsedMs=\(elapsedMs)")
    }

    static func logIngest(rows: Int, elapsedMs: Int) {
        print("[AnalyticsGRDB] ingest rows=\(rows) elapsedMs=\(elapsedMs)")
    }

    static func logQuery(rows: Int, elapsedMs: Int) {
        print("[AnalyticsGRDB] query rows=\(rows) elapsedMs=\(elapsedMs)")
    }

    static func logDatabaseBytes(_ bytes: Int64) {
        print("[AnalyticsGRDB] dbBytes=\(bytes)")
    }

    static func logShadowParity(
        viewerID: String,
        range: String,
        mode: String,
        rpcRows: Int,
        localRows: Int,
        revision: Int64,
        coverage: Bool,
        parity: Bool,
        elapsedMs: Int
    ) {
        print(
            "[AnalyticsGRDB][ShadowParity] viewer=\(viewerID) range=\(range) mode=\(mode) " +
                "rpcRows=\(rpcRows) localRows=\(localRows) revision=\(revision) " +
                "coverage=\(coverage) parity=\(parity) elapsedMs=\(elapsedMs)"
        )
    }

    static func logShadowMismatch(_ detail: String) {
        print("[AnalyticsGRDB][ShadowParity] mismatch \(detail)")
    }

    static func logShadowIngestFailure(_ message: String) {
        print("[AnalyticsGRDB] shadow ingest failed \(message)")
    }

    static func logLogoutCleanupFailure(_ message: String) {
        print("[AnalyticsGRDB] logout cleanup failed \(message)")
    }

    static func logDashboardBootstrapIngest(metricsRows: Int, chartBundles: Int, elapsedMs: Int) {
        print(
            "[AnalyticsGRDB] dashboardBootstrap metricsRows=\(metricsRows) " +
                "chartBundles=\(chartBundles) elapsedMs=\(elapsedMs)"
        )
    }

    static func logAccountChartsIngest(bundles: Int, elapsedMs: Int) {
        print("[AnalyticsGRDB] accountCharts bundles=\(bundles) elapsedMs=\(elapsedMs)")
    }

    static func logDashboardShadowParity(
        viewerID: String,
        revision: Int64,
        aggregatePresets: Int,
        accountPresets: Int,
        chartBundles: Int,
        parity: Bool,
        elapsedMs: Int
    ) {
        print(
            "[AnalyticsGRDB][DashboardShadowParity] viewer=\(viewerID) revision=\(revision) " +
                "aggregatePresets=\(aggregatePresets) accountPresets=\(accountPresets) " +
                "chartBundles=\(chartBundles) parity=\(parity) elapsedMs=\(elapsedMs)"
        )
    }

    static func logAccountChartsShadowParity(
        viewerID: String,
        account: String,
        revision: Int64,
        presets: Int,
        parity: Bool,
        elapsedMs: Int
    ) {
        print(
            "[AnalyticsGRDB][AccountChartsShadowParity] viewer=\(viewerID) account=\(account) " +
                "revision=\(revision) presets=\(presets) parity=\(parity) elapsedMs=\(elapsedMs)"
        )
    }

    static func logStorageEstimate(sqliteBytes: Int64, walBytes: Int64) {
        print(
            "[AnalyticsGRDB] storageEstimate sqliteBytes=\(sqliteBytes) walBytes=\(walBytes) " +
                "totalBytes=\(sqliteBytes + walBytes)"
        )
    }

    static func logReadPerf(
        domain: String,
        rows: Int?,
        metricsRows: Int?,
        chartBundles: Int?,
        bundles: Int?,
        elapsedMs: Int
    ) {
        var parts = ["domain=\(domain)", "elapsedMs=\(elapsedMs)"]
        if let rows { parts.append("rows=\(rows)") }
        if let metricsRows { parts.append("metricsRows=\(metricsRows)") }
        if let chartBundles { parts.append("chartBundles=\(chartBundles)") }
        if let bundles { parts.append("bundles=\(bundles)") }
        print("[AnalyticsGRDB][ReadPerf] " + parts.joined(separator: " "))
    }

    static func logCalendarReadParity(
        viewerID: String,
        range: String,
        requiredRevision: Int64,
        state: AnalyticsLocalReadState,
        localRows: Int,
        currentRows: Int,
        parity: Bool,
        elapsedMs: Int
    ) {
        print(
            "[AnalyticsGRDB][CalendarReadParity] viewer=\(viewerID) range=\(range) " +
                "requiredRevision=\(requiredRevision) state=\(state) localRows=\(localRows) " +
                "currentRows=\(currentRows) parity=\(parity) elapsedMs=\(elapsedMs)"
        )
    }

    static func logDashboardReadParity(
        viewerID: String,
        revision: Int64,
        scope: String,
        preset: String,
        state: AnalyticsLocalReadState,
        parity: Bool,
        elapsedMs: Int
    ) {
        print(
            "[AnalyticsGRDB][DashboardReadParity] viewer=\(viewerID) revision=\(revision) " +
                "scope=\(scope) preset=\(preset) state=\(state) parity=\(parity) elapsedMs=\(elapsedMs)"
        )
    }

    static func logAccountChartsReadParity(
        viewerID: String,
        account: String,
        revision: Int64,
        state: AnalyticsLocalReadState,
        presets: Int,
        parity: Bool,
        elapsedMs: Int
    ) {
        print(
            "[AnalyticsGRDB][AccountChartsReadParity] viewer=\(viewerID) account=\(account) " +
                "revision=\(revision) state=\(state) presets=\(presets) parity=\(parity) " +
                "elapsedMs=\(elapsedMs)"
        )
    }
}
#else
nonisolated enum AnalyticsGRDBProbe {
    static func logOpen(elapsedMs: Int) {}
    static func logMigration(elapsedMs: Int) {}
    static func logIngest(rows: Int, elapsedMs: Int) {}
    static func logQuery(rows: Int, elapsedMs: Int) {}
    static func logDatabaseBytes(_ bytes: Int64) {}
    static func logShadowParity(
        viewerID: String,
        range: String,
        mode: String,
        rpcRows: Int,
        localRows: Int,
        revision: Int64,
        coverage: Bool,
        parity: Bool,
        elapsedMs: Int
    ) {}
    static func logShadowMismatch(_ detail: String) {}
    static func logShadowIngestFailure(_ message: String) {}
    static func logLogoutCleanupFailure(_ message: String) {}
    static func logDashboardBootstrapIngest(metricsRows: Int, chartBundles: Int, elapsedMs: Int) {}
    static func logAccountChartsIngest(bundles: Int, elapsedMs: Int) {}
    static func logDashboardShadowParity(
        viewerID: String,
        revision: Int64,
        aggregatePresets: Int,
        accountPresets: Int,
        chartBundles: Int,
        parity: Bool,
        elapsedMs: Int
    ) {}
    static func logAccountChartsShadowParity(
        viewerID: String,
        account: String,
        revision: Int64,
        presets: Int,
        parity: Bool,
        elapsedMs: Int
    ) {}
    static func logStorageEstimate(sqliteBytes: Int64, walBytes: Int64) {}
    static func logReadPerf(
        domain: String,
        rows: Int?,
        metricsRows: Int?,
        chartBundles: Int?,
        bundles: Int?,
        elapsedMs: Int
    ) {}
    static func logCalendarReadParity(
        viewerID: String,
        range: String,
        requiredRevision: Int64,
        state: AnalyticsLocalReadState,
        localRows: Int,
        currentRows: Int,
        parity: Bool,
        elapsedMs: Int
    ) {}
    static func logDashboardReadParity(
        viewerID: String,
        revision: Int64,
        scope: String,
        preset: String,
        state: AnalyticsLocalReadState,
        parity: Bool,
        elapsedMs: Int
    ) {}
    static func logAccountChartsReadParity(
        viewerID: String,
        account: String,
        revision: Int64,
        state: AnalyticsLocalReadState,
        presets: Int,
        parity: Bool,
        elapsedMs: Int
    ) {}
}
#endif
