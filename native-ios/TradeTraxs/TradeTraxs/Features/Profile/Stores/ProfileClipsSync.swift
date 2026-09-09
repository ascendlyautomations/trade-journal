import Foundation

#if DEBUG
/// DEBUG tracing for owner Profile Clips publish / refresh synchronization.
nonisolated enum ProfileClipsSync {
    static func log(_ message: String) {
        print("[ProfileClips] \(message)")
    }

    static func logFetch(userID: String, count: Int, newPublishedReelID: String?) {
        log("fetch userID=\(userID) count=\(count)")
        if let newPublishedReelID {
            log("newPublishedReelFound=\(count > 0)") // refined per-reel below
            _ = newPublishedReelID
        }
    }

    static func logReel(id: String, videoPresent: Bool, thumbnailPresent: Bool) {
        log("reel id=\(id) videoPresent=\(videoPresent) thumbnailPresent=\(thumbnailPresent)")
    }

    static func logNewPublishedReelFound(_ found: Bool, reelID: String) {
        log("newPublishedReelFound=\(found) reelID=\(reelID)")
    }

    static func logPublishSucceeded(id: String, visibleBefore: Int, optimisticAfter: Int) {
        log("publishSucceeded id=\(id)")
        log("visibleBefore=\(visibleBefore)")
        log("optimisticAfter=\(optimisticAfter)")
    }

    static func logAuthoritativeRefreshStarted(generation: UInt64) {
        log("authoritativeRefreshStarted generation=\(generation)")
    }

    static func logAuthoritativeReturned(generation: UInt64, count: Int) {
        log("authoritativeReturned generation=\(generation) count=\(count)")
    }

    static func logStaleResponseDropped(generation: UInt64, currentGeneration: UInt64) {
        log("staleResponseDropped generation=\(generation) current=\(currentGeneration)")
    }

    static func logReconciled(beforeCount: Int, snapshotCount: Int, afterCount: Int) {
        log("reconciledCount before=\(beforeCount) snapshot=\(snapshotCount) after=\(afterCount)")
    }

    static func logUIVisibleCount(_ count: Int) {
        log("UIVisibleCount=\(count)")
    }
}
#else
nonisolated enum ProfileClipsSync {
    static func log(_ message: String) {}
    static func logFetch(userID: String, count: Int, newPublishedReelID: String?) {}
    static func logReel(id: String, videoPresent: Bool, thumbnailPresent: Bool) {}
    static func logNewPublishedReelFound(_ found: Bool, reelID: String) {}
    static func logPublishSucceeded(id: String, visibleBefore: Int, optimisticAfter: Int) {}
    static func logAuthoritativeRefreshStarted(generation: UInt64) {}
    static func logAuthoritativeReturned(generation: UInt64, count: Int) {}
    static func logStaleResponseDropped(generation: UInt64, currentGeneration: UInt64) {}
    static func logReconciled(beforeCount: Int, snapshotCount: Int, afterCount: Int) {}
    static func logUIVisibleCount(_ count: Int) {}
}
#endif
