import Foundation

nonisolated enum DashboardAnalyticsGRDBLoader {
    struct Presentation: Sendable {
        var readState: AnalyticsLocalReadState
        var revision: Int64?
        var snapshot: AnalyticsLocalDashboardV3Snapshot?
        var bootstrap: AnalyticsDashboardBootstrapV3?
        var canRender: Bool
        var elapsedMs: Int
    }

    static func loadPresentation(
        viewerID: ProfileID,
        diskEnvelope: AnalyticsDashboardBootstrapV3?,
        sessionAccounts: [TradingAccount],
        store: AnalyticsLocalStore? = nil
    ) async -> Presentation {
        let store = store ?? AnalyticsLocalStore.sharedStore()
        do {
            let read = try await store.readDashboardSnapshotForPresentation(viewerID: viewerID)
            guard read.canRenderLocally, let snapshot = read.snapshot, let revision = read.effectiveRevision else {
                return Presentation(
                    readState: read.state,
                    revision: read.effectiveRevision,
                    snapshot: nil,
                    bootstrap: nil,
                    canRender: false,
                    elapsedMs: read.elapsedMs
                )
            }
            let bootstrap = DashboardAnalyticsGRDBMapper.bootstrap(
                snapshot: snapshot,
                viewerID: viewerID,
                diskEnvelope: diskEnvelope,
                sessionAccounts: sessionAccounts
            )
            return Presentation(
                readState: read.state,
                revision: revision,
                snapshot: snapshot,
                bootstrap: bootstrap,
                canRender: true,
                elapsedMs: read.elapsedMs
            )
        } catch {
            return Presentation(
                readState: .missing,
                revision: nil,
                snapshot: nil,
                bootstrap: nil,
                canRender: false,
                elapsedMs: 0
            )
        }
    }

    static func loadAccountCharts(
        viewerID: ProfileID,
        accountID: TradingAccountID,
        revision: Int64,
        store: AnalyticsLocalStore? = nil
    ) async -> AnalyticsDashboardAccountChartsReadResult? {
        let store = store ?? AnalyticsLocalStore.sharedStore()
        return try? await store.readDashboardAccountCharts(
            viewerID: viewerID,
            accountID: accountID,
            requiredRevision: revision
        )
    }

    static func loadAggregateCharts(
        viewerID: ProfileID,
        revision: Int64,
        store: AnalyticsLocalStore? = nil
    ) async -> AnalyticsDashboardAccountChartsReadResult? {
        let store = store ?? AnalyticsLocalStore.sharedStore()
        return try? await store.readDashboardAggregateCharts(
            viewerID: viewerID,
            requiredRevision: revision
        )
    }
}
