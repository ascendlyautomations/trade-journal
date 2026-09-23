import Foundation

nonisolated protocol AnalyticsRevisionSeeding: Sendable {
    func seedHighWaterRevision(viewerID: ProfileID) async -> AnalyticsRevisionSeed
}

/// GRDB sync high-water first, then persisted dashboard revision, else zero.
nonisolated struct DefaultAnalyticsRevisionSeeder: AnalyticsRevisionSeeding {
    func seedHighWaterRevision(viewerID: ProfileID) async -> AnalyticsRevisionSeed {
        if let sync = try? await AnalyticsLocalStore.sharedStore().syncState(viewerID: viewerID) {
            return AnalyticsRevisionSeed(
                highWaterRevision: sync.server_revision,
                source: "grdb_analytics_sync_state"
            )
        }
        if let blob = DashboardAnalyticsDiskCache.load(viewerID: viewerID) {
            return AnalyticsRevisionSeed(
                highWaterRevision: blob.revision,
                source: "dashboard_analytics_disk_cache"
            )
        }
        return AnalyticsRevisionSeed(highWaterRevision: 0, source: "unknown_zero")
    }
}
