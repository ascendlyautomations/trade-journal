import Foundation

#if DEBUG
/// DEBUG tracing for owner Profile Posts publish / refresh synchronization.
nonisolated enum ProfilePostsSync {
    static func log(_ message: String) {
        print("[ProfilePostsSync] \(message)")
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
nonisolated enum ProfilePostsSync {
    static func log(_ message: String) {}
    static func logPublishSucceeded(id: String, visibleBefore: Int, optimisticAfter: Int) {}
    static func logAuthoritativeRefreshStarted(generation: UInt64) {}
    static func logAuthoritativeReturned(generation: UInt64, count: Int) {}
    static func logStaleResponseDropped(generation: UInt64, currentGeneration: UInt64) {}
    static func logReconciled(beforeCount: Int, snapshotCount: Int, afterCount: Int) {}
    static func logUIVisibleCount(_ count: Int) {}
}
#endif
