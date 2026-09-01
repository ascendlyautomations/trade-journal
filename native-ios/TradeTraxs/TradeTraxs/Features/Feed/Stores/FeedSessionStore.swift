import Foundation

/// Session memory for Feed timeline — survives tab switches within the authenticated session.
@MainActor
final class FeedSessionStore {
    static let shared = FeedSessionStore()

    struct Snapshot: Sendable {
        var cacheKey: String
        var entries: [FeedTimelineEntry]
        var stories: [Story]
        var nextCursor: String?
        var loadedAt: Date
    }

    private var snapshots: [String: Snapshot] = [:]

    private init() {}

    static func cacheKey(
        viewerID: ProfileID,
        scope: FeedScope,
        contentFilter: FeedContentFilter,
        cursor: String?
    ) -> String {
        "\(viewerID.rawValue)|\(scope.rawValue)|\(contentFilter.rawValue)|\(cursor ?? "-")"
    }

    func restore(key: String) -> Snapshot? {
        snapshots[key]
    }

    func save(_ snapshot: Snapshot) {
        snapshots[snapshot.cacheKey] = snapshot
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            let prefix = viewerID.rawValue + "|"
            snapshots = snapshots.filter { !$0.key.hasPrefix(prefix) }
        } else {
            snapshots = [:]
        }
    }
}
