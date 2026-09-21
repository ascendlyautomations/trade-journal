#if DEBUG
import Foundation

/// Concise DEBUG summaries for Feed persistent cache + reconciliation.
@MainActor
enum FeedPersistentCacheProbe {
    private(set) static var hit = false
    private(set) static var itemCount = 0
    private(set) static var ageMs: Int = 0
    private(set) static var firstRenderMs: Int = 0
    private(set) static var reconcileMs: Int = 0
    private(set) static var inserted = 0
    private(set) static var updated = 0
    private(set) static var removed = 0
    private(set) static var source: String = "none"
    /// When true, feed disk writes complete before `persist` returns (unit tests only).
    static var forceSynchronousDisk = false

    static func resetForTesting() {
        hit = false
        itemCount = 0
        ageMs = 0
        firstRenderMs = 0
        reconcileMs = 0
        inserted = 0
        updated = 0
        removed = 0
        source = "none"
        forceSynchronousDisk = false
    }

    static func recordDiskHit(items: Int, ageMs value: Int, firstRenderMs renderMs: Int) {
        hit = true
        itemCount = items
        ageMs = value
        firstRenderMs = renderMs
        source = "disk"
        print(
            "[FeedPersistentCache] hit=true items=\(items) ageMs=\(value)"
        )
        print("[FeedPersistentCache] firstRenderMs=\(renderMs)")
        print("[FeedPersistentCache] source=disk")
    }

    static func recordNetworkBootstrap(items: Int) {
        hit = false
        itemCount = items
        source = "network"
        print("[FeedPersistentCache] hit=false items=\(items) ageMs=0")
        print("[FeedPersistentCache] source=network")
    }

    static func recordReconcile(
        inserted: Int,
        updated: Int,
        removed: Int,
        durationMs: Int
    ) {
        self.inserted = inserted
        self.updated = updated
        self.removed = removed
        reconcileMs = durationMs
        DiskCacheIOProbe.noteReconciliation()
        print(
            "[FeedPersistentCache] reconcileMs=\(durationMs) inserted=\(inserted) updated=\(updated) removed=\(removed)"
        )
    }
}
#endif
