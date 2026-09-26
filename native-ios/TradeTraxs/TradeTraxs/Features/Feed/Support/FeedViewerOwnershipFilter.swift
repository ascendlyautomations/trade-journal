import Foundation

/// Viewer-specific rule: the authenticated user must never see their own feed timeline rows.
enum FeedViewerOwnershipFilter {
    static func isOwnContent(entry: FeedTimelineEntry, viewerID: ProfileID) -> Bool {
        entry.authorProfileID == viewerID
    }

    static func filterEntries(
        _ entries: [FeedTimelineEntry],
        viewerID: ProfileID?
    ) -> [FeedTimelineEntry] {
        guard let viewerID else { return entries }
        return entries.filter { !isOwnContent(entry: $0, viewerID: viewerID) }
    }
}
