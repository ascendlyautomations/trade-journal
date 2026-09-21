import Foundation

nonisolated enum LocalAnalyticsRevisionAuthority: Sendable, Equatable {
    case known(revision: Int64, source: String)
    case unknown(source: String)

    var revisionIfKnown: Int64? {
        switch self {
        case .known(let revision, _): return revision
        case .unknown: return nil
        }
    }

    var sourceLabel: String {
        switch self {
        case .known(_, let source): return source
        case .unknown(let source): return source
        }
    }
}

extension DefaultAnalyticsRevisionSeeder {
    func localRevisionAuthority(viewerID: ProfileID) async -> LocalAnalyticsRevisionAuthority {
        if let sync = try? await AnalyticsLocalStore().syncState(viewerID: viewerID) {
            return .known(
                revision: sync.server_revision,
                source: "grdb_analytics_sync_state"
            )
        }
        if let blob = DashboardAnalyticsDiskCache.load(viewerID: viewerID) {
            return .known(
                revision: blob.revision,
                source: "dashboard_analytics_disk_cache"
            )
        }
        return .unknown(source: "missing_local_material")
    }
}
