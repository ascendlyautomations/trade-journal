import Foundation

/// Gates Feed image prefetch until first-screen media has settled (cache, success, or failure).
@MainActor
enum FeedImageViewportReadiness {
    private static var generation: UInt64 = 0
    private static var pendingMediaEntryIDs: Set<String> = []
    private static var isReady = true

    static var allowsPrefetch: Bool { isReady }

    /// Registers media-bearing rows expected in the first viewport (~first 8 entries, up to 4 with media).
    static func registerInitialViewport(entries: [FeedTimelineEntry]) {
        generation &+= 1
        let mediaEntries = entries
            .prefix(8)
            .filter(\.hasDisplayMedia)
            .prefix(4)
            .map(\.id)
        pendingMediaEntryIDs = Set(mediaEntries)
        isReady = pendingMediaEntryIDs.isEmpty
    }

    static func noteMediaResolved(entryID: String, outcome: Outcome) {
        guard pendingMediaEntryIDs.contains(entryID) else { return }
        pendingMediaEntryIDs.remove(entryID)
        if pendingMediaEntryIDs.isEmpty {
            isReady = true
        }
        _ = outcome
    }

    enum Outcome: Sendable {
        case cacheHit
        case loaded
        case failed
    }

    static func resetForTesting() {
        generation = 0
        pendingMediaEntryIDs = []
        isReady = true
    }
}
